defmodule FirehoseSimulator.MetricsTest do
  use ExUnit.Case, async: false

  alias FirehoseSimulator.Metrics

  setup do
    reset_metrics_state()
    on_exit(&reset_metrics_state/0)
    :ok
  end

  test "snapshot reports zero percentiles when the rolling window is empty" do
    snapshot = Metrics.snapshot()

    assert snapshot.worker_query_window_stats.p95_latency_ms == 0
    assert snapshot.worker_query_window_stats.p99_latency_ms == 0
  end

  test "snapshot reports matching percentiles for a single query sample" do
    emit_query(42)

    snapshot = Metrics.snapshot()

    assert snapshot.worker_query_window_stats.p95_latency_ms == 42
    assert snapshot.worker_query_window_stats.p99_latency_ms == 42
  end

  test "snapshot computes rolling p95 and p99 using nearest-rank percentiles" do
    Enum.each(1..100, &emit_query/1)

    snapshot = Metrics.snapshot()

    assert snapshot.worker_query_window_stats.query_count == 100
    assert snapshot.worker_query_window_stats.p95_latency_ms == 95
    assert snapshot.worker_query_window_stats.p99_latency_ms == 99

    assert snapshot.worker_query_window_stats.p99_latency_ms >=
             snapshot.worker_query_window_stats.p95_latency_ms
  end

  defp emit_query(latency_ms) do
    :telemetry.execute(
      [:firehose_simulator, :worker, :query],
      %{latency_ms: latency_ms, rows: 1},
      %{status: :ok, player_id: "player-1"}
    )

    _ = :sys.get_state(Metrics)
  end

  defp reset_metrics_state do
    :sys.replace_state(Metrics, fn _state ->
      %{
        json_files_loaded: 0,
        player_load: 0,
        player_start: 0,
        player_pause: 0,
        player_stop: 0,
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
        worker_query_by_status: %{},
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
    end)
  end
end
