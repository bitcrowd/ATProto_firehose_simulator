defmodule FirehoseSimulator.MetricsTest do
  use ExUnit.Case, async: false

  alias FirehoseSimulator.Metrics

  test "aggregates lifecycle counters and active session gauges from telemetry" do
    before_snapshot = Metrics.snapshot()

    :telemetry.execute(
      [:firehose_simulator, :event_feeder, :inject],
      %{sessions_started: 3},
      %{player_id: "player-metrics", elapsed_ms: 100}
    )

    :telemetry.execute(
      [:firehose_simulator, :worker, :cycle],
      %{session_count: 3, ok: 0, errors: 0, completed: 2, timeouts: 0, duration_ms: 10},
      %{partition: 0, player_id: "player-metrics"}
    )

    :telemetry.execute(
      [:firehose_simulator, :player, :stop],
      %{count: 1, active_sessions_cleared: 1},
      %{player_id: "player-metrics"}
    )

    after_snapshot =
      await_snapshot(fn snapshot ->
        snapshot.active_sessions_total == before_snapshot.active_sessions_total and
          not Map.has_key?(snapshot.active_sessions_by_player, "player-metrics")
      end)

    assert after_snapshot.event_feeder_sessions_started >=
             before_snapshot.event_feeder_sessions_started + 3

    assert after_snapshot.worker_cycle_completed >= before_snapshot.worker_cycle_completed + 2
    assert after_snapshot.active_sessions_total == before_snapshot.active_sessions_total
    refute Map.has_key?(after_snapshot.active_sessions_by_player, "player-metrics")
  end

  test "clamps active session gauges at zero when decrements exceed current count" do
    :telemetry.execute(
      [:firehose_simulator, :worker, :cycle],
      %{session_count: 0, ok: 0, errors: 0, completed: 50, timeouts: 0},
      %{partition: 0, player_id: "player-clamp"}
    )

    snapshot =
      await_snapshot(fn current ->
        current.active_sessions_total == 0 and
          not Map.has_key?(current.active_sessions_by_player, "player-clamp")
      end)

    assert snapshot.active_sessions_total == 0
    refute Map.has_key?(snapshot.active_sessions_by_player, "player-clamp")
  end

  test "aggregates worker query window stats" do
    before_snapshot = Metrics.snapshot()

    :telemetry.execute(
      [:firehose_simulator, :worker, :query],
      %{latency_ms: 12, rows: 2, lag_ms: 25},
      %{status: :ok, player_id: "player-lag"}
    )

    :telemetry.execute(
      [:firehose_simulator, :worker, :query],
      %{latency_ms: 20, rows: 0, lag_ms: 1_500},
      %{status: :error, player_id: "player-lag", reason: "boom"}
    )

    after_snapshot = Metrics.snapshot()

    assert after_snapshot.worker_query_total_count == before_snapshot.worker_query_total_count + 2
    assert after_snapshot.worker_query_window_stats.max_lag_ms >= 1_500
  end

  defp await_snapshot(predicate, timeout_ms \\ 1_000) when is_function(predicate, 1) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_await_snapshot(predicate, deadline)
  end

  defp do_await_snapshot(predicate, deadline) do
    snapshot = Metrics.snapshot()

    if predicate.(snapshot) do
      snapshot
    else
      if System.monotonic_time(:millisecond) >= deadline do
        flunk("timed out waiting for metrics snapshot to match predicate")
      end

      receive do
      after
        10 -> do_await_snapshot(predicate, deadline)
      end
    end
  end
end
