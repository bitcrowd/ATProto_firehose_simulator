defmodule FirehoseSimulator.MetricsTest do
  use ExUnit.Case, async: false

  alias FirehoseSimulator.Metrics

  test "aggregates lifecycle counters and active session gauges from telemetry" do
    before_snapshot = Metrics.snapshot()

    :telemetry.execute(
      [:firehose_simulator, :json, :file, :loaded],
      %{count: 1},
      %{path: "/tmp/scenario.json", kind: "scenario"}
    )

    :telemetry.execute(
      [:firehose_simulator, :player, :load],
      %{count: 1},
      %{player_id: "player-metrics", scenario_id: nil, schedulers: 1}
    )

    :telemetry.execute(
      [:firehose_simulator, :player, :start],
      %{count: 1},
      %{player_id: "player-metrics", from_state: :loaded}
    )

    :telemetry.execute(
      [:firehose_simulator, :player, :pause],
      %{count: 1},
      %{player_id: "player-metrics"}
    )

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
        snapshot.player_stop >= before_snapshot.player_stop + 1 and
          snapshot.active_sessions_total == before_snapshot.active_sessions_total
      end)

    assert after_snapshot.json_files_loaded == before_snapshot.json_files_loaded + 1
    assert after_snapshot.player_load == before_snapshot.player_load + 1
    assert after_snapshot.player_start == before_snapshot.player_start + 1
    assert after_snapshot.player_pause == before_snapshot.player_pause + 1
    assert after_snapshot.player_stop == before_snapshot.player_stop + 1

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

  test "aggregates worker query lag totals, buckets, and window stats" do
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

    assert after_snapshot.worker_query_lag_total_ms ==
             before_snapshot.worker_query_lag_total_ms + 1_525

    assert bucket_delta(after_snapshot, before_snapshot, "0") == 0
    assert bucket_delta(after_snapshot, before_snapshot, "10") == 0
    assert bucket_delta(after_snapshot, before_snapshot, "50") == 1
    assert bucket_delta(after_snapshot, before_snapshot, "100") == 1
    assert bucket_delta(after_snapshot, before_snapshot, "500") == 1
    assert bucket_delta(after_snapshot, before_snapshot, "1000") == 1
    assert bucket_delta(after_snapshot, before_snapshot, "5000") == 2
    assert bucket_delta(after_snapshot, before_snapshot, "10000") == 2
    assert bucket_delta(after_snapshot, before_snapshot, "+Inf") == 2

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

  defp bucket_delta(after_snapshot, before_snapshot, bucket) do
    Map.fetch!(after_snapshot.worker_query_lag_bucket_counts, bucket) -
      Map.fetch!(before_snapshot.worker_query_lag_bucket_counts, bucket)
  end
end
