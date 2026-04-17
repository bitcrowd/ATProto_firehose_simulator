defmodule FirehoseSimulator.Metrics do
  @moduledoc false

  use GenServer

  require Logger

  @handler_id "firehose-simulator-metrics"
  @worker_query_lag_buckets [0, 10, 50, 100, 500, 1_000, 5_000, 10_000]
  @telemetry_events [
    [:firehose_simulator, :json, :file, :loaded],
    [:firehose_simulator, :player, :load],
    [:firehose_simulator, :player, :start],
    [:firehose_simulator, :player, :pause],
    [:firehose_simulator, :player, :stop],
    [:firehose_simulator, :event_feeder, :inject],
    [:firehose_simulator, :event_feeder, :posts, :dispatch],
    [:firehose_simulator, :event_feeder, :posts, :complete],
    [:firehose_simulator, :event_feeder, :follows, :dispatch],
    [:firehose_simulator, :event_feeder, :follows, :complete],
    [:firehose_simulator, :worker, :query],
    [:firehose_simulator, :worker, :cycle]
  ]
  @worker_query_window_ms 60_000

  @type snapshot :: map()

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  @spec snapshot() :: snapshot()
  def snapshot do
    GenServer.call(__MODULE__, :snapshot)
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
        {:ok, default_state()}

      {:error, :already_exists} ->
        :ok = :telemetry.detach(@handler_id)

        :ok =
          :telemetry.attach_many(
            @handler_id,
            @telemetry_events,
            &__MODULE__.handle_telemetry/4,
            %{}
          )

        {:ok, default_state()}
    end
  end

  @impl true
  def terminate(_reason, _state) do
    :telemetry.detach(@handler_id)
    :ok
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    now_ms = System.system_time(:millisecond)
    state = prune_worker_query_window(state, now_ms)
    {:reply, present_state(state), state}
  end

  @impl true
  def handle_cast({:telemetry_json_file_loaded, measurements, metadata}, state) do
    next_state =
      Map.update!(state, :json_files_loaded, &(&1 + measurement_value(measurements, :count)))

    Logger.debug(
      "[metrics] json.file.loaded total=#{next_state.json_files_loaded} measurements=#{inspect(measurements)} metadata=#{inspect(metadata)}"
    )

    {:noreply, next_state}
  end

  @impl true
  def handle_cast({:telemetry_player_load, measurements, metadata}, state) do
    next_state =
      Map.update!(state, :player_load, &(&1 + measurement_value(measurements, :count)))

    Logger.debug(
      "[metrics] player.load total=#{next_state.player_load} measurements=#{inspect(measurements)} metadata=#{inspect(metadata)}"
    )

    {:noreply, next_state}
  end

  def handle_cast({:telemetry_player_start, measurements, metadata}, state) do
    next_state =
      Map.update!(state, :player_start, &(&1 + measurement_value(measurements, :count)))

    Logger.debug(
      "[metrics] player.start total=#{next_state.player_start} measurements=#{inspect(measurements)} metadata=#{inspect(metadata)}"
    )

    {:noreply, next_state}
  end

  def handle_cast({:telemetry_player_pause, measurements, metadata}, state) do
    next_state =
      Map.update!(state, :player_pause, &(&1 + measurement_value(measurements, :count)))

    Logger.debug(
      "[metrics] player.pause total=#{next_state.player_pause} measurements=#{inspect(measurements)} metadata=#{inspect(metadata)}"
    )

    {:noreply, next_state}
  end

  def handle_cast({:telemetry_player_stop, measurements, metadata}, state) do
    cleared = measurement_value(measurements, :active_sessions_cleared)

    next_state =
      state
      |> Map.update!(:player_stop, &(&1 + measurement_value(measurements, :count)))
      |> drop_active_sessions(player_id(metadata), cleared)

    Logger.debug(
      "[metrics] player.stop total=#{next_state.player_stop} cleared=#{cleared} measurements=#{inspect(measurements)} metadata=#{inspect(metadata)}"
    )

    {:noreply, next_state}
  end

  def handle_cast({:telemetry_event_feeder_inject, measurements, metadata}, state) do
    sessions_started = measurement_value(measurements, :sessions_started)

    next_state =
      state
      |> Map.update!(:event_feeder_inject_count, &(&1 + 1))
      |> add_measurement(:event_feeder_sessions_started, measurements, :sessions_started)
      |> update_active_sessions(player_id(metadata), sessions_started)

    Logger.debug(
      "[metrics] event_feeder.inject count=#{next_state.event_feeder_inject_count} measurements=#{inspect(measurements)} metadata=#{inspect(metadata)}"
    )

    {:noreply, next_state}
  end

  def handle_cast({:telemetry_event_feeder_posts_dispatch, measurements, metadata}, state) do
    next_state =
      state
      |> Map.update!(:event_feeder_posts_dispatch_count, &(&1 + 1))
      |> add_measurement(:event_feeder_posts_dispatched, measurements, :events_dispatched)

    Logger.debug(
      "[metrics] event_feeder.posts.dispatch count=#{next_state.event_feeder_posts_dispatch_count} measurements=#{inspect(measurements)} metadata=#{inspect(metadata)}"
    )

    {:noreply, next_state}
  end

  def handle_cast({:telemetry_event_feeder_posts_complete, measurements, metadata}, state) do
    next_state =
      state
      |> Map.update!(:event_feeder_posts_complete_count, &(&1 + 1))
      |> add_measurement(:event_feeder_posts_ok, measurements, :ok)
      |> add_measurement(:event_feeder_posts_error, measurements, :error)

    Logger.debug(
      "[metrics] event_feeder.posts.complete count=#{next_state.event_feeder_posts_complete_count} measurements=#{inspect(measurements)} metadata=#{inspect(metadata)}"
    )

    {:noreply, next_state}
  end

  def handle_cast({:telemetry_event_feeder_follows_dispatch, measurements, metadata}, state) do
    next_state =
      state
      |> Map.update!(:event_feeder_follows_dispatch_count, &(&1 + 1))
      |> add_measurement(:event_feeder_follows_dispatched, measurements, :events_dispatched)

    Logger.debug(
      "[metrics] event_feeder.follows.dispatch count=#{next_state.event_feeder_follows_dispatch_count} measurements=#{inspect(measurements)} metadata=#{inspect(metadata)}"
    )

    {:noreply, next_state}
  end

  def handle_cast({:telemetry_event_feeder_follows_complete, measurements, metadata}, state) do
    next_state =
      state
      |> Map.update!(:event_feeder_follows_complete_count, &(&1 + 1))
      |> add_measurement(:event_feeder_follows_ok, measurements, :ok)
      |> add_measurement(:event_feeder_follows_error, measurements, :error)

    Logger.debug(
      "[metrics] event_feeder.follows.complete count=#{next_state.event_feeder_follows_complete_count} measurements=#{inspect(measurements)} metadata=#{inspect(metadata)}"
    )

    {:noreply, next_state}
  end

  def handle_cast({:telemetry_worker_query, measurements, metadata}, state) do
    now_ms = System.system_time(:millisecond)
    status = normalize_query_status(metadata)
    rows = measurement_value(measurements, :rows)
    latency_ms = measurement_value(measurements, :latency_ms)
    lag_ms = measurement_value(measurements, :lag_ms)
    sample = %{ts_ms: now_ms, latency_ms: latency_ms, lag_ms: lag_ms, status: status}

    next_state =
      state
      |> Map.update!(:worker_query_total_count, &(&1 + 1))
      |> Map.update!(:worker_query_rows, &(&1 + rows))
      |> Map.update!(:worker_query_total_latency_ms, &(&1 + latency_ms))
      |> Map.update!(:worker_query_lag_total_ms, &(&1 + lag_ms))
      |> Map.update!(:worker_query_by_status, fn acc ->
        Map.update(acc, status, 1, &(&1 + 1))
      end)
      |> Map.update!(:worker_query_lag_bucket_counts, &increment_lag_buckets(&1, lag_ms))
      |> Map.update!(:worker_query_window, &:queue.in(sample, &1))
      |> prune_worker_query_window(now_ms)

    Logger.debug(
      "[metrics] worker.query total_count=#{next_state.worker_query_total_count} status=#{status} rows=#{rows} latency_ms=#{latency_ms} lag_ms=#{lag_ms}"
    )

    {:noreply, next_state}
  end

  def handle_cast({:telemetry_worker_cycle, measurements, metadata}, state) do
    partition = normalize_partition(metadata)
    completed = measurement_value(measurements, :completed)

    next_state =
      state
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
      |> update_active_sessions(player_id(metadata), -completed)

    Logger.debug(
      "[metrics] worker.cycle count=#{next_state.worker_cycle_count} partition=#{partition} measurements=#{inspect(measurements)}"
    )

    {:noreply, next_state}
  end

  @doc false
  def handle_telemetry(
        [:firehose_simulator, :json, :file, :loaded],
        measurements,
        metadata,
        _config
      ) do
    GenServer.cast(__MODULE__, {:telemetry_json_file_loaded, measurements, metadata})
  end

  def handle_telemetry(
        [:firehose_simulator, :player, :load],
        measurements,
        metadata,
        _config
      ) do
    GenServer.cast(__MODULE__, {:telemetry_player_load, measurements, metadata})
  end

  def handle_telemetry(
        [:firehose_simulator, :player, :start],
        measurements,
        metadata,
        _config
      ) do
    GenServer.cast(__MODULE__, {:telemetry_player_start, measurements, metadata})
  end

  def handle_telemetry(
        [:firehose_simulator, :player, :pause],
        measurements,
        metadata,
        _config
      ) do
    GenServer.cast(__MODULE__, {:telemetry_player_pause, measurements, metadata})
  end

  def handle_telemetry(
        [:firehose_simulator, :player, :stop],
        measurements,
        metadata,
        _config
      ) do
    GenServer.cast(__MODULE__, {:telemetry_player_stop, measurements, metadata})
  end

  def handle_telemetry(
        [:firehose_simulator, :event_feeder, :inject],
        measurements,
        metadata,
        _config
      ) do
    GenServer.cast(__MODULE__, {:telemetry_event_feeder_inject, measurements, metadata})
  end

  def handle_telemetry(
        [:firehose_simulator, :event_feeder, :posts, :dispatch],
        measurements,
        metadata,
        _config
      ) do
    GenServer.cast(__MODULE__, {:telemetry_event_feeder_posts_dispatch, measurements, metadata})
  end

  def handle_telemetry(
        [:firehose_simulator, :event_feeder, :posts, :complete],
        measurements,
        metadata,
        _config
      ) do
    GenServer.cast(__MODULE__, {:telemetry_event_feeder_posts_complete, measurements, metadata})
  end

  def handle_telemetry(
        [:firehose_simulator, :event_feeder, :follows, :dispatch],
        measurements,
        metadata,
        _config
      ) do
    GenServer.cast(
      __MODULE__,
      {:telemetry_event_feeder_follows_dispatch, measurements, metadata}
    )
  end

  def handle_telemetry(
        [:firehose_simulator, :event_feeder, :follows, :complete],
        measurements,
        metadata,
        _config
      ) do
    GenServer.cast(
      __MODULE__,
      {:telemetry_event_feeder_follows_complete, measurements, metadata}
    )
  end

  def handle_telemetry([:firehose_simulator, :worker, :query], measurements, metadata, _config) do
    GenServer.cast(__MODULE__, {:telemetry_worker_query, measurements, metadata})
  end

  def handle_telemetry([:firehose_simulator, :worker, :cycle], measurements, metadata, _config) do
    GenServer.cast(__MODULE__, {:telemetry_worker_cycle, measurements, metadata})
  end

  defp present_state(state) do
    Map.put(
      state,
      :worker_query_window_stats,
      worker_query_window_stats(state.worker_query_window)
    )
  end

  defp default_state do
    %{
      json_files_loaded: 0,
      player_load: 0,
      player_start: 0,
      player_pause: 0,
      player_stop: 0,
      active_sessions_total: 0,
      active_sessions_by_player: %{},
      event_feeder_inject_count: 0,
      event_feeder_sessions_started: 0,
      event_feeder_posts_dispatch_count: 0,
      event_feeder_posts_dispatched: 0,
      event_feeder_posts_complete_count: 0,
      event_feeder_posts_ok: 0,
      event_feeder_posts_error: 0,
      event_feeder_follows_dispatch_count: 0,
      event_feeder_follows_dispatched: 0,
      event_feeder_follows_complete_count: 0,
      event_feeder_follows_ok: 0,
      event_feeder_follows_error: 0,
      worker_query_total_count: 0,
      worker_query_rows: 0,
      worker_query_total_latency_ms: 0,
      worker_query_lag_total_ms: 0,
      worker_query_by_status: %{},
      worker_query_lag_bucket_counts: lag_bucket_counts_template(),
      worker_query_window: :queue.new(),
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

  defp player_id(metadata) do
    case Map.get(metadata, :player_id) do
      player_id when is_binary(player_id) -> player_id
      _other -> nil
    end
  end

  defp prune_worker_query_window(state, now_ms) do
    cutoff_ms = now_ms - @worker_query_window_ms
    %{state | worker_query_window: do_prune_window(state.worker_query_window, cutoff_ms)}
  end

  defp do_prune_window(queue, cutoff_ms) do
    case :queue.peek(queue) do
      {:value, %{ts_ms: ts_ms}} when ts_ms < cutoff_ms ->
        {_dropped, queue} = :queue.out(queue)
        do_prune_window(queue, cutoff_ms)

      _other ->
        queue
    end
  end

  defp worker_query_window_stats(queue) do
    samples = :queue.to_list(queue)
    query_count = length(samples)
    status_counts = count_query_statuses(samples)
    latencies = Enum.map(samples, & &1.latency_ms)
    lags = Enum.map(samples, & &1.lag_ms)
    sum_latency_ms = Enum.sum(latencies)
    sum_lag_ms = Enum.sum(lags)

    %{
      window_ms: @worker_query_window_ms,
      query_count: query_count,
      ok_count: Map.get(status_counts, "ok", 0),
      error_count: Map.get(status_counts, "error", 0),
      timeout_count: Map.get(status_counts, "timeout", 0),
      exit_count: Map.get(status_counts, "exit", 0),
      avg_latency_ms: ratio(sum_latency_ms, query_count),
      p95_latency_ms: percentile(latencies, 0.95),
      p99_latency_ms: percentile(latencies, 0.99),
      avg_lag_ms: ratio(sum_lag_ms, query_count),
      p95_lag_ms: percentile(lags, 0.95),
      max_lag_ms: Enum.max(lags, fn -> 0 end),
      error_rate_pct:
        ratio(
          Map.get(status_counts, "error", 0) +
            Map.get(status_counts, "timeout", 0) +
            Map.get(status_counts, "exit", 0),
          query_count
        ),
      timeout_rate_pct: ratio(Map.get(status_counts, "timeout", 0), query_count)
    }
  end

  defp count_query_statuses(samples) do
    Enum.reduce(samples, %{}, fn %{status: status}, acc ->
      Map.update(acc, status, 1, &(&1 + 1))
    end)
  end

  defp percentile([], _quantile), do: 0

  defp percentile(latencies, quantile) do
    sorted = Enum.sort(latencies)
    n = length(sorted)
    rank = max(1, ceil(n * quantile))
    Enum.at(sorted, rank - 1, 0)
  end

  defp ratio(_numerator, 0), do: 0.0
  defp ratio(numerator, denominator), do: Float.round(numerator / denominator, 2)

  defp lag_bucket_counts_template do
    @worker_query_lag_buckets
    |> Enum.map(&{Integer.to_string(&1), 0})
    |> Kernel.++([{"+Inf", 0}])
    |> Map.new()
  end

  defp increment_lag_buckets(counts, lag_ms) do
    counts =
      Enum.reduce(@worker_query_lag_buckets, counts, fn bucket, acc ->
        if lag_ms <= bucket do
          Map.update!(acc, Integer.to_string(bucket), &(&1 + 1))
        else
          acc
        end
      end)

    Map.update!(counts, "+Inf", &(&1 + 1))
  end

  defp update_active_sessions(state, nil, _delta), do: state

  defp update_active_sessions(state, _player_id, 0), do: state

  defp update_active_sessions(state, player_id, delta) when is_binary(player_id) do
    next_total = max(state.active_sessions_total + delta, 0)

    next_by_player =
      case max(Map.get(state.active_sessions_by_player, player_id, 0) + delta, 0) do
        0 -> Map.delete(state.active_sessions_by_player, player_id)
        count -> Map.put(state.active_sessions_by_player, player_id, count)
      end

    %{state | active_sessions_total: next_total, active_sessions_by_player: next_by_player}
  end

  defp drop_active_sessions(state, nil, cleared) do
    %{state | active_sessions_total: max(state.active_sessions_total - cleared, 0)}
  end

  defp drop_active_sessions(state, player_id, cleared) when is_binary(player_id) do
    %{
      state
      | active_sessions_total: max(state.active_sessions_total - cleared, 0),
        active_sessions_by_player: Map.delete(state.active_sessions_by_player, player_id)
    }
  end
end
