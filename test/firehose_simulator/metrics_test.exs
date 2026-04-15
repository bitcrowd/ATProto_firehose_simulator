defmodule FirehoseSimulator.MetricsTest do
  use ExUnit.Case, async: false

  alias FirehoseSimulator.Metrics

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

  defp bucket_delta(after_snapshot, before_snapshot, bucket) do
    Map.fetch!(after_snapshot.worker_query_lag_bucket_counts, bucket) -
      Map.fetch!(before_snapshot.worker_query_lag_bucket_counts, bucket)
  end
end
