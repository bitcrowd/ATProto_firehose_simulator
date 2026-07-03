defmodule FirehoseSimulator.Player do
  @moduledoc """
  Context for player.

  Player takes a scenario and manages its lifecycle.
  """

  alias FirehoseSimulator.Player.EventFeeder
  alias FirehoseSimulator.Player.Scheduler.Supervisor, as: SchedulerSupervisor
  alias FirehoseSimulator.Player.Scheduler.Worker
  alias FirehoseSimulator.Player.Store
  alias FirehoseSimulator.PlayerSupervisor
  alias FirehoseSimulator.Scenario
  alias FirehoseSimulator.State
  require Logger

  @registry FirehoseSimulator.Player.Registry

  @type lifecycle_state :: :loaded | :running | :paused
  @type lifecycle_metadata :: %{
          player_id: String.t(),
          scenario_id: String.t() | nil,
          lifecycle_state: lifecycle_state(),
          request_interval_ms: non_neg_integer(),
          timeline_limit: non_neg_integer(),
          schedulers: pos_integer(),
          supervisor: pid(),
          loaded_at: integer(),
          started_at: integer() | nil,
          paused_at: integer() | nil,
          total_paused: non_neg_integer()
        }
  @type load_result :: {:ok, String.t(), lifecycle_metadata()} | {:error, term()}

  @spec load(Scenario.t(), keyword()) :: load_result()
  def load(%Scenario{} = scenario, opts \\ []) do
    player_id = next_player_id()
    scheduler_count = Keyword.get(opts, :scheduler_count, System.schedulers_online())
    request_interval_ms = scenario.request_interval_ms || 30_000
    timeline_limit = scenario.timeline_limit || 20
    worker_max_concurrency = Keyword.get(opts, :worker_max_concurrency)
    worker_batch_size = Keyword.get(opts, :worker_batch_size, Keyword.get(opts, :batch_size))
    scenario_id = Keyword.get(opts, :scenario_id)

    event_feeder_opts = [
      player_id: player_id,
      scenario: scenario,
      request_interval_ms: request_interval_ms,
      timeline_limit: timeline_limit,
      scheduler_count: scheduler_count
    ]

    scheduler_opts = [
      name: via(player_id, :scheduler_supervisor),
      player_id: player_id,
      store_name: via(player_id, :store),
      event_feeder_name: via(player_id, :event_feeder),
      scheduler_count: scheduler_count,
      event_feeder_opts: event_feeder_opts
    ]

    scheduler_opts =
      if is_integer(worker_max_concurrency) and worker_max_concurrency > 0 do
        Keyword.put(scheduler_opts, :worker_max_concurrency, worker_max_concurrency)
      else
        scheduler_opts
      end

    scheduler_opts =
      if is_integer(worker_batch_size) and worker_batch_size > 0 do
        Keyword.put(scheduler_opts, :worker_batch_size, worker_batch_size)
      else
        scheduler_opts
      end

    child_spec = %{
      id: {:simulation_player, player_id},
      start: {SchedulerSupervisor, :start_link, [scheduler_opts]},
      restart: :temporary
    }

    case DynamicSupervisor.start_child(PlayerSupervisor, child_spec) do
      {:ok, supervisor_pid} ->
        loaded_at = System.system_time(:millisecond)

        metadata = %{
          player_id: player_id,
          scenario_id: scenario_id,
          request_interval_ms: request_interval_ms,
          timeline_limit: timeline_limit,
          schedulers: scheduler_count,
          supervisor: supervisor_pid,
          lifecycle_state: :loaded,
          loaded_at: loaded_at,
          started_at: nil,
          paused_at: nil,
          total_paused: 0
        }

        :ok = State.put_player(player_id, metadata)

        :telemetry.execute(
          [:firehose_simulator, :player, :load],
          %{count: 1},
          %{
            player_id: player_id,
            scenario_id: scenario_id,
            schedulers: scheduler_count,
            request_interval_ms: request_interval_ms,
            timeline_limit: timeline_limit
          }
        )

        Logger.info("[player #{player_id}] loaded scheduler_count=#{scheduler_count}")

        {:ok, player_id, metadata}

      error ->
        error
    end
  end

  @spec start(String.t()) :: :ok | {:error, term()}
  def start(player_id) when is_binary(player_id) do
    with {:ok, metadata} <- player_metadata(player_id),
         {:ok, state} <- ensure_startable(metadata),
         :ok <- start_workers(player_id),
         :ok <- EventFeeder.start(via(player_id, :event_feeder)) do
      now = System.system_time(:millisecond)

      next_metadata =
        case state do
          :loaded ->
            metadata
            |> Map.put(:lifecycle_state, :running)
            |> Map.put(:started_at, now)
            |> Map.put(:paused_at, nil)
            |> Map.put(:total_paused, 0)

          :paused ->
            metadata
            |> Map.put(:lifecycle_state, :running)
            |> Map.put(:paused_at, nil)
            |> Map.update!(:total_paused, &(&1 + (now - metadata.paused_at)))
        end

      :ok = State.put_player(player_id, next_metadata)

      :telemetry.execute(
        [:firehose_simulator, :player, :start],
        %{count: 1},
        %{player_id: player_id, from_state: state}
      )

      Logger.info("[player #{player_id}] started from=#{state}")
      :ok
    end
  end

  @spec pause(String.t()) :: :ok | {:error, term()}
  def pause(player_id) when is_binary(player_id) do
    with {:ok, metadata} <- player_metadata(player_id),
         :ok <- ensure_transition(metadata, :running, :pause),
         :ok <- EventFeeder.pause(via(player_id, :event_feeder)),
         :ok <- pause_workers(player_id) do
      now = System.system_time(:millisecond)

      next_metadata =
        metadata
        |> Map.put(:lifecycle_state, :paused)
        |> Map.put(:paused_at, now)

      :ok = State.put_player(player_id, next_metadata)

      :telemetry.execute(
        [:firehose_simulator, :player, :pause],
        %{count: 1},
        %{player_id: player_id}
      )

      Logger.info("[player #{player_id}] paused")
      :ok
    end
  end

  @spec stop(String.t()) :: :ok | {:error, term()}
  def stop(player_id) when is_binary(player_id) do
    active_sessions_cleared = safe_store_count(via(player_id, :store), :active)

    with {:ok, supervisor_pid} <- scheduler_pid(player_id),
         :ok <- DynamicSupervisor.terminate_child(PlayerSupervisor, supervisor_pid) do
      :ok = State.delete_player(player_id)

      :telemetry.execute(
        [:firehose_simulator, :player, :stop],
        %{count: 1, active_sessions_cleared: active_sessions_cleared},
        %{player_id: player_id}
      )

      Logger.info("[player #{player_id}] stopped")
      :ok
    else
      {:error, :not_running} ->
        _ = State.delete_player(player_id)
        {:error, :not_loaded}

      error ->
        error
    end
  end

  @spec stop_all() :: :ok
  def stop_all do
    State.list_players()
    |> Map.keys()
    |> Enum.each(fn player_id -> _ = stop(player_id) end)

    :ok
  end

  @spec status(String.t()) :: map() | {:error, :not_loaded}
  def status(player_id) when is_binary(player_id) do
    with {:ok, metadata} <- player_metadata(player_id) do
      store_name = via(player_id, :store)
      feeder_name = via(player_id, :event_feeder)

      feeder_status =
        if process_alive?(feeder_name) do
          EventFeeder.status(feeder_name)
        else
          %{lifecycle_state: metadata.lifecycle_state, started?: false, effective_elapsed: 0}
        end

      %{
        player_id: player_id,
        lifecycle_state: metadata.lifecycle_state,
        loaded?: true,
        running?: metadata.lifecycle_state == :running,
        paused?: metadata.lifecycle_state == :paused,
        active_sessions: safe_store_count(store_name, :active),
        completed_sessions: safe_store_count(store_name, :completed),
        feeder: feeder_status,
        metadata: metadata
      }
    end
  end

  @spec active_sessions_total() :: non_neg_integer()
  def active_sessions_total do
    active_sessions_by_player()
    |> Map.values()
    |> Enum.sum()
  end

  @spec active_sessions_by_player() :: %{optional(String.t()) => non_neg_integer()}
  def active_sessions_by_player do
    State.list_players()
    |> Map.keys()
    |> Enum.map(fn player_id ->
      {player_id, safe_store_count(via(player_id, :store), :active)}
    end)
    |> Map.new()
  end

  defp ensure_startable(%{lifecycle_state: lifecycle_state})
       when lifecycle_state in [:loaded, :paused],
       do: {:ok, lifecycle_state}

  defp ensure_startable(%{lifecycle_state: lifecycle_state}),
    do: {:error, {:invalid_state_transition, lifecycle_state, :start}}

  defp ensure_transition(%{lifecycle_state: expected}, expected, _action), do: :ok

  defp ensure_transition(%{lifecycle_state: actual}, _expected, action),
    do: {:error, {:invalid_state_transition, actual, action}}

  defp player_metadata(player_id) do
    case State.list_players() do
      %{^player_id => metadata} -> {:ok, metadata}
      _ -> {:error, :not_loaded}
    end
  end

  defp start_workers(player_id) do
    player_id
    |> worker_names()
    |> Enum.each(&Worker.start_processing/1)

    :ok
  end

  defp pause_workers(player_id) do
    player_id
    |> worker_names()
    |> Enum.each(&Worker.pause_processing/1)

    :ok
  end

  defp worker_names(player_id) do
    case player_metadata(player_id) do
      {:ok, metadata} ->
        for partition <- 0..(metadata.schedulers - 1) do
          via(player_id, {:worker, partition})
        end

      _ ->
        []
    end
  end

  defp scheduler_pid(player_id) do
    lookup(player_id, :scheduler_supervisor)
  end

  defp lookup(player_id, role) do
    case Registry.lookup(@registry, {player_id, role}) do
      [{pid, _value}] -> {:ok, pid}
      [] -> {:error, :not_running}
    end
  end

  defp process_alive?(name) do
    case GenServer.whereis(name) do
      nil -> false
      pid -> Process.alive?(pid)
    end
  end

  defp safe_store_count(store_name, kind) do
    case GenServer.whereis(store_name) do
      nil ->
        0

      _pid ->
        case kind do
          :active -> Store.count_active(store_name)
          :completed -> Store.count_completed(store_name)
        end
    end
  end

  defp via(player_id, role) do
    {:via, Registry, {@registry, {player_id, role}}}
  end

  defp next_player_id do
    "player-" <> Integer.to_string(System.unique_integer([:positive, :monotonic]))
  end
end
