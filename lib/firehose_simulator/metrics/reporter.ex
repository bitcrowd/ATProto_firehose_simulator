defmodule FirehoseSimulator.Metrics.Reporter do
  @moduledoc false

  use GenServer

  require Logger

  @handler_id "firehose-simulator-metrics-reporter"
  @sample_interval_ms 1_000
  @telemetry_events [
    [:firehose_simulator, :event_feeder, :inject],
    [:firehose_simulator, :worker, :query],
    [:firehose_simulator, :worker, :cycle]
  ]

  @type finalize_reason :: :stop | :reset
  @type run_metadata :: map()

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  @spec start_run(String.t(), run_metadata()) :: :ok
  def start_run(player_id, metadata) when is_binary(player_id) and is_map(metadata) do
    GenServer.call(__MODULE__, {:start_run, player_id, metadata})
  end

  @spec finalize_run(String.t(), finalize_reason()) :: {:ok, String.t()} | {:error, term()}
  def finalize_run(player_id, reason)
      when is_binary(player_id) and reason in [:stop, :reset] do
    GenServer.call(__MODULE__, {:finalize_run, player_id, reason}, :infinity)
  end

  @spec active_run?(String.t()) :: boolean()
  def active_run?(player_id) when is_binary(player_id) do
    GenServer.call(__MODULE__, {:active_run?, player_id})
  end

  @spec reset() :: :ok
  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  @impl true
  def init(:ok) do
    case :telemetry.attach_many(
           @handler_id,
           @telemetry_events,
           &__MODULE__.handle_telemetry/4,
           %{}
         ) do
      :ok ->
        {:ok, %{runs: %{}}}

      {:error, :already_exists} ->
        :ok = :telemetry.detach(@handler_id)

        :ok =
          :telemetry.attach_many(
            @handler_id,
            @telemetry_events,
            &__MODULE__.handle_telemetry/4,
            %{}
          )

        {:ok, %{runs: %{}}}
    end
  end

  @impl true
  def terminate(_reason, _state) do
    :telemetry.detach(@handler_id)
    :ok
  end

  @impl true
  def handle_call({:start_run, player_id, metadata}, _from, state) do
    now_ms = System.system_time(:millisecond)

    run =
      case Map.get(state.runs, player_id) do
        nil ->
          schedule_sample(player_id, @sample_interval_ms)

          %{
            player_id: player_id,
            started_at_ms: now_ms,
            metadata: metadata,
            counters: default_counters(),
            timeline: [],
            finalized?: false,
            report_path: nil
          }

        existing ->
          existing
      end

    {:reply, :ok, put_in(state, [:runs, player_id], run)}
  end

  def handle_call({:active_run?, player_id}, _from, state) do
    run = Map.get(state.runs, player_id)
    active? = is_map(run) and run.finalized? == false
    {:reply, active?, state}
  end

  def handle_call({:finalize_run, player_id, reason}, _from, state) do
    case Map.get(state.runs, player_id) do
      nil ->
        {:reply, {:error, :run_not_found}, state}

      %{finalized?: true, report_path: path} = _run when is_binary(path) ->
        {:reply, {:ok, path}, state}

      run ->
        now_ms = System.system_time(:millisecond)
        run = maybe_append_sample(run, now_ms)
        report = build_report(run, now_ms, reason)

        case write_report(report, reason) do
          {:ok, path} ->
            finalized_run = %{run | finalized?: true, report_path: path}
            next_state = put_in(state, [:runs, player_id], finalized_run)
            {:reply, {:ok, path}, next_state}

          {:error, _reason} = error ->
            {:reply, error, state}
        end
    end
  end

  def handle_call(:reset, _from, _state) do
    {:reply, :ok, %{runs: %{}}}
  end

  @impl true
  def handle_cast({:telemetry_event, event, measurements, metadata}, state) do
    player_id = metadata_player_id(metadata)

    next_state =
      if is_binary(player_id) do
        update_in(state, [:runs, player_id], fn
          nil -> nil
          run -> %{run | counters: apply_telemetry(run.counters, event, measurements, metadata)}
        end)
      else
        state
      end

    {:noreply, next_state}
  end

  @impl true
  def handle_info({:sample, player_id}, state) do
    now_ms = System.system_time(:millisecond)

    next_state =
      update_in(state, [:runs, player_id], fn
        nil ->
          nil

        %{finalized?: true} = run ->
          run

        run ->
          schedule_sample(player_id, @sample_interval_ms)
          append_sample(run, now_ms)
      end)

    {:noreply, next_state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @doc false
  def handle_telemetry(event, measurements, metadata, _config) do
    GenServer.cast(__MODULE__, {:telemetry_event, event, measurements, metadata})
  end

  defp schedule_sample(player_id, interval_ms) do
    Process.send_after(self(), {:sample, player_id}, interval_ms)
  end

  defp write_report(report, reason) do
    finalized_at_ms = Map.fetch!(report, :finalized_at_ms)
    player_id = Map.fetch!(report, :player_id)
    reports_dir = reports_dir()
    filename = "#{sanitize(player_id)}-#{finalized_at_ms}-#{reason}.json"
    relative_path = Path.join(reports_dir, filename)
    absolute_path = Path.expand(relative_path)

    with :ok <- File.mkdir_p(reports_dir),
         {:ok, json} <- Jason.encode(report),
         :ok <- File.write(absolute_path, json) do
      {:ok, absolute_path}
    else
      {:error, reason} = error ->
        Logger.warning("[metrics.reporter] failed to write report: #{inspect(reason)}")
        error
    end
  end

  defp build_report(run, finalized_at_ms, reason) do
    %{
      version: 1,
      player_id: run.player_id,
      plan_id: Map.get(run.metadata, :simulation_plan_id),
      reason: to_string(reason),
      started_at_ms: run.started_at_ms,
      finalized_at_ms: finalized_at_ms,
      duration_ms: max(finalized_at_ms - run.started_at_ms, 0),
      run_metadata: sanitize_for_json(run.metadata),
      summary: run.counters,
      timeline: Enum.reverse(run.timeline)
    }
  end

  defp append_sample(run, now_ms) do
    sample = sample(run, now_ms)
    %{run | timeline: [sample | run.timeline]}
  end

  defp maybe_append_sample(run, now_ms) do
    case run.timeline do
      [%{ts_ms: ts_ms} | _rest] when ts_ms == now_ms -> run
      _other -> append_sample(run, now_ms)
    end
  end

  defp sample(run, now_ms) do
    counters = run.counters

    %{
      ts_ms: now_ms,
      elapsed_ms: max(now_ms - run.started_at_ms, 0),
      worker_query_total_count: counters.worker_query_total_count,
      worker_query_rows: counters.worker_query_rows,
      worker_query_total_latency_ms: counters.worker_query_total_latency_ms,
      worker_query_by_status: counters.worker_query_by_status,
      worker_cycle_count: counters.worker_cycle_count,
      worker_cycle_session_count: counters.worker_cycle_session_count,
      worker_cycle_ok: counters.worker_cycle_ok,
      worker_cycle_errors: counters.worker_cycle_errors,
      worker_cycle_completed: counters.worker_cycle_completed,
      worker_cycle_timeouts: counters.worker_cycle_timeouts,
      worker_cycle_duration_ms: counters.worker_cycle_duration_ms,
      worker_cycle_by_partition: counters.worker_cycle_by_partition,
      event_feeder_inject_count: counters.event_feeder_inject_count,
      event_feeder_sessions_started: counters.event_feeder_sessions_started,
      event_feeder_posts_ok: counters.event_feeder_posts_ok,
      event_feeder_posts_error: counters.event_feeder_posts_error,
      event_feeder_follows_ok: counters.event_feeder_follows_ok,
      event_feeder_follows_error: counters.event_feeder_follows_error
    }
  end

  defp apply_telemetry(
         counters,
         [:firehose_simulator, :event_feeder, :inject],
         measurements,
         _meta
       ) do
    counters
    |> Map.update!(:event_feeder_inject_count, &(&1 + 1))
    |> add_measurement(:event_feeder_sessions_started, measurements, :sessions_started)
    |> add_measurement(:event_feeder_posts_ok, measurements, :posts_ok)
    |> add_measurement(:event_feeder_posts_error, measurements, :posts_error)
    |> add_measurement(:event_feeder_follows_ok, measurements, :follows_ok)
    |> add_measurement(:event_feeder_follows_error, measurements, :follows_error)
  end

  defp apply_telemetry(counters, [:firehose_simulator, :worker, :query], measurements, metadata) do
    status = normalize_query_status(metadata)

    counters
    |> Map.update!(:worker_query_total_count, &(&1 + 1))
    |> add_measurement(:worker_query_rows, measurements, :rows)
    |> add_measurement(:worker_query_total_latency_ms, measurements, :latency_ms)
    |> Map.update!(:worker_query_by_status, fn acc ->
      Map.update(acc, status, 1, &(&1 + 1))
    end)
  end

  defp apply_telemetry(counters, [:firehose_simulator, :worker, :cycle], measurements, metadata) do
    partition = normalize_partition(metadata)

    counters
    |> Map.update!(:worker_cycle_count, &(&1 + 1))
    |> add_measurement(:worker_cycle_session_count, measurements, :session_count)
    |> add_measurement(:worker_cycle_ok, measurements, :ok)
    |> add_measurement(:worker_cycle_errors, measurements, :errors)
    |> add_measurement(:worker_cycle_completed, measurements, :completed)
    |> add_measurement(:worker_cycle_timeouts, measurements, :timeouts)
    |> add_measurement(:worker_cycle_duration_ms, measurements, :duration_ms)
    |> Map.update!(:worker_cycle_by_partition, fn acc ->
      Map.update(acc, partition, 1, &(&1 + 1))
    end)
  end

  defp apply_telemetry(counters, _event, _measurements, _metadata), do: counters

  defp default_counters do
    %{
      event_feeder_inject_count: 0,
      event_feeder_sessions_started: 0,
      event_feeder_posts_ok: 0,
      event_feeder_posts_error: 0,
      event_feeder_follows_ok: 0,
      event_feeder_follows_error: 0,
      worker_query_total_count: 0,
      worker_query_rows: 0,
      worker_query_total_latency_ms: 0,
      worker_query_by_status: %{},
      worker_cycle_count: 0,
      worker_cycle_session_count: 0,
      worker_cycle_ok: 0,
      worker_cycle_errors: 0,
      worker_cycle_completed: 0,
      worker_cycle_timeouts: 0,
      worker_cycle_duration_ms: 0,
      worker_cycle_by_partition: %{}
    }
  end

  defp metadata_player_id(metadata) when is_map(metadata) do
    case Map.get(metadata, :player_id) do
      player_id when is_binary(player_id) -> player_id
      player_id when is_atom(player_id) -> Atom.to_string(player_id)
      _other -> nil
    end
  end

  defp add_measurement(state, state_key, measurements, measurement_key) do
    Map.update!(state, state_key, &(&1 + measurement_value(measurements, measurement_key)))
  end

  defp measurement_value(measurements, key) do
    case Map.get(measurements, key, 0) do
      value when is_integer(value) -> value
      _other -> 0
    end
  end

  defp normalize_query_status(metadata) do
    case metadata |> Map.get(:status, :unknown) |> to_string() do
      "ok" -> "ok"
      "timeout" -> "timeout"
      "exit" -> "exit"
      _other -> "error"
    end
  end

  defp normalize_partition(metadata) do
    metadata
    |> Map.get(:partition, "unknown")
    |> to_string()
  end

  defp reports_dir do
    Application.get_env(:firehose_simulator, :simulation_reports_dir, "tmp/simulation_reports")
  end

  defp sanitize(player_id) do
    String.replace(player_id, ~r/[^A-Za-z0-9\-_]/, "_")
  end

  defp sanitize_for_json(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, item}, acc ->
      Map.put(acc, key, sanitize_for_json(item))
    end)
  end

  defp sanitize_for_json(value) when is_list(value) do
    Enum.map(value, &sanitize_for_json/1)
  end

  defp sanitize_for_json(value) when is_pid(value), do: inspect(value)
  defp sanitize_for_json(value) when is_reference(value), do: inspect(value)

  defp sanitize_for_json(value) when is_tuple(value),
    do: value |> Tuple.to_list() |> sanitize_for_json()

  defp sanitize_for_json(value), do: value
end
