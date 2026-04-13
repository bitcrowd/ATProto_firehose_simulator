defmodule FirehoseSimulator.Player do
  @moduledoc """
  Context for player.

  Player takes a scenario and runs it.
  """

  require Logger

  alias FirehoseSimulator.Metrics
  alias FirehoseSimulator.PlayerSupervisor
  alias FirehoseSimulator.Player.Scheduler.Supervisor, as: SchedulerSupervisor
  alias FirehoseSimulator.Scenario
  alias FirehoseSimulator.Player.EventFeeder
  alias FirehoseSimulator.State
  alias FirehoseSimulator.Player.Store

  @registry FirehoseSimulator.Player.Registry

  @type play_result :: {:ok, String.t(), map()} | {:error, term()}

  @spec play(Scenario.t(), keyword()) :: play_result()
  def play(%Scenario{} = scenario, opts \\ []) do
    player_id = next_player_id()
    scheduler_count = Keyword.get(opts, :scheduler_count, System.schedulers_online())
    request_interval_ms = scenario.request_interval_ms || 30_000
    worker_max_concurrency = Keyword.get(opts, :worker_max_concurrency)
    scenario_id = Keyword.get(opts, :scenario_id)

    event_feeder_opts = [
      player_id: player_id,
      scenario: scenario,
      request_interval_ms: request_interval_ms,
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

    child_spec = %{
      id: {:simulation_player, player_id},
      start: {SchedulerSupervisor, :start_link, [scheduler_opts]},
      restart: :temporary
    }

    case DynamicSupervisor.start_child(PlayerSupervisor, child_spec) do
      {:ok, supervisor_pid} ->
        :ok = EventFeeder.start_feeding(via(player_id, :event_feeder))

        metadata = %{
          player_id: player_id,
          scenario_id: scenario_id,
          request_interval_ms: request_interval_ms,
          schedulers: scheduler_count,
          supervisor: supervisor_pid,
          started?: true,
          started_at_ms: System.system_time(:millisecond)
        }

        :ok = State.put_running_player(player_id, metadata)

        :ok =
          Metrics.increment(:player_start, %{
            player_id: player_id,
            scheduler_count: scheduler_count
          })

        Logger.info("[player #{player_id}] started scheduler_count=#{scheduler_count}")

        {:ok, player_id, metadata}

      error ->
        error
    end
  end

  @spec stop(String.t()) :: :ok | {:error, term()}
  def stop(player_id) when is_binary(player_id) do
    with {:ok, supervisor_pid} <- scheduler_pid(player_id),
         :ok <- DynamicSupervisor.terminate_child(PlayerSupervisor, supervisor_pid) do
      :ok = State.delete_running_player(player_id)
      :ok = Metrics.increment(:player_stop, %{player_id: player_id})
      Logger.info("[player #{player_id}] stopped")
      :ok
    else
      {:error, :not_running} = error ->
        _ = State.delete_running_player(player_id)
        error

      error ->
        error
    end
  end

  @spec reset(String.t()) :: :ok | {:error, term()}
  def reset(player_id) when is_binary(player_id) do
    case scheduler_pid(player_id) do
      {:ok, supervisor_pid} ->
        case DynamicSupervisor.terminate_child(PlayerSupervisor, supervisor_pid) do
          :ok ->
            :ok = State.delete_running_player(player_id)
            :ok = Metrics.increment(:player_reset, %{player_id: player_id})
            Logger.info("[player #{player_id}] reset")
            :ok

          error ->
            error
        end

      {:error, :not_running} = error ->
        _ = State.delete_running_player(player_id)
        error
    end
  end

  @spec stop_all() :: :ok
  def stop_all do
    State.list_running_players()
    |> Map.keys()
    |> Enum.each(fn player_id -> _ = stop(player_id) end)

    :ok
  end

  @spec reset_all() :: :ok
  def reset_all do
    State.list_running_players()
    |> Map.keys()
    |> Enum.each(fn player_id -> _ = reset(player_id) end)

    :ok
  end

  @spec status(String.t()) :: map() | {:error, :not_running}
  def status(player_id) when is_binary(player_id) do
    running? = match?({:ok, _pid}, scheduler_pid(player_id))
    store_name = via(player_id, :store)
    feeder_name = via(player_id, :event_feeder)
    loaded? = process_alive?(feeder_name)

    feeder_status =
      if loaded? do
        EventFeeder.status(feeder_name)
      else
        %{started?: false}
      end

    %{
      player_id: player_id,
      running?: running?,
      loaded?: loaded?,
      active_sessions: safe_store_count(store_name, :active),
      completed_sessions: safe_store_count(store_name, :completed),
      feeder: feeder_status
    }
  end

  @spec active_sessions_total() :: non_neg_integer()
  def active_sessions_total do
    active_sessions_by_player()
    |> Map.values()
    |> Enum.sum()
  end

  @spec active_sessions_by_player() :: %{optional(String.t()) => non_neg_integer()}
  def active_sessions_by_player do
    State.list_running_players()
    |> Map.keys()
    |> Enum.map(fn player_id ->
      {player_id, safe_store_count(via(player_id, :store), :active)}
    end)
    |> Map.new()
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
