defmodule FirehoseSimulator.Metrics.PrometheusExporterTest do
  use ExUnit.Case, async: false

  import Plug.Test

  alias FirehoseSimulator.Metrics
  alias FirehoseSimulator.Metrics.PrometheusExporter

  test "exports metrics in prometheus text format" do
    :telemetry.execute(
      [:firehose_simulator, :event_feeder, :posts, :dispatch],
      %{events_dispatched: 2},
      %{player_id: "player-1", elapsed_ms: 10}
    )

    :telemetry.execute(
      [:firehose_simulator, :event_feeder, :posts, :complete],
      %{ok: 2, error: 1},
      %{player_id: "player-1"}
    )

    :telemetry.execute(
      [:firehose_simulator, :event_feeder, :follows, :dispatch],
      %{events_dispatched: 3},
      %{player_id: "player-1", elapsed_ms: 10}
    )

    :telemetry.execute(
      [:firehose_simulator, :event_feeder, :follows, :complete],
      %{ok: 3, error: 0},
      %{player_id: "player-1"}
    )

    :telemetry.execute(
      [:firehose_simulator, :worker, :query],
      %{latency_ms: 10, rows: 2, lag_ms: 25},
      %{status: :ok, player_id: "player-1"}
    )

    :telemetry.execute(
      [:firehose_simulator, :worker, :cycle],
      %{session_count: 1, ok: 1, errors: 0, completed: 0, timeouts: 0, duration_ms: 5},
      %{partition: 0, player_id: "player-1"}
    )

    _snapshot = Metrics.snapshot()

    conn = conn(:get, "/metrics")
    conn = PrometheusExporter.call(conn, PrometheusExporter.init([]))
    body = conn.resp_body

    assert conn.status == 200
    assert ["text/plain; charset=utf-8"] = Plug.Conn.get_resp_header(conn, "content-type")

    assert body =~ "firehose_simulator_player_start_total"
    assert body =~ "firehose_simulator_event_feeder_inject_total"
    assert body =~ "firehose_simulator_event_feeder_posts_dispatch_total"
    assert body =~ "firehose_simulator_event_feeder_posts_complete_total"
    assert body =~ "firehose_simulator_event_feeder_follows_dispatch_total"
    assert body =~ "firehose_simulator_event_feeder_follows_complete_total"
    assert body =~ "firehose_simulator_worker_query_by_status{status=\"ok\"}"

    assert body =~
             "firehose_simulator_worker_query_lag_ms_bucket{kind=\"session_request\",le=\"50\"}"

    assert body =~ "firehose_simulator_worker_query_lag_ms_count{kind=\"session_request\"}"
    assert body =~ "firehose_simulator_worker_query_lag_ms_sum{kind=\"session_request\"}"
    assert body =~ "firehose_simulator_worker_query_window_avg_lag_ms"
    assert body =~ "firehose_simulator_worker_query_window_p95_lag_ms"
    assert body =~ "firehose_simulator_worker_query_window_max_lag_ms"
    assert body =~ "firehose_simulator_worker_cycle_by_partition{partition=\"0\"}"
    assert body =~ "firehose_simulator_worker_query_window_p95_latency_ms"
    assert body =~ "firehose_simulator_worker_query_window_p99_latency_ms"
    assert body =~ "firehose_simulator_active_sessions"
  end
end
