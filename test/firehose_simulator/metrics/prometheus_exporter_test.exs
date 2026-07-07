defmodule FirehoseSimulator.Metrics.PrometheusExporterTest do
  use ExUnit.Case, async: false
  import Plug.Test
  alias FirehoseSimulator.Metrics.PrometheusExporter

  test "returns 200 for GET /metrics" do
    conn = conn(:get, "/metrics") |> PrometheusExporter.call(PrometheusExporter.init([]))

    assert conn.status == 200
  end

  test "returns 404 for other paths" do
    conn = conn(:get, "/other") |> PrometheusExporter.call(PrometheusExporter.init([]))

    assert conn.status == 404
  end

  test "exports firehose simulator metrics after telemetry events" do
    :telemetry.execute(
      [:firehose_simulator, :event_feeder, :posts, :dispatch],
      %{events_dispatched: 2},
      %{player_id: "player-prom-test", elapsed_ms: 10}
    )

    :telemetry.execute(
      [:firehose_simulator, :event_feeder, :posts, :complete],
      %{ok: 2, error: 0},
      %{player_id: "player-prom-test"}
    )

    :telemetry.execute(
      [:firehose_simulator, :event_feeder, :follows, :dispatch],
      %{events_dispatched: 3},
      %{player_id: "player-prom-test", elapsed_ms: 10}
    )

    :telemetry.execute(
      [:firehose_simulator, :event_feeder, :follows, :complete],
      %{ok: 3, error: 0},
      %{player_id: "player-prom-test"}
    )

    :telemetry.execute(
      [:firehose_simulator, :worker, :query],
      %{latency_ms: 10, rows: 2, lag_ms: 25},
      %{status: :ok, player_id: "player-prom-test"}
    )

    :telemetry.execute(
      [:firehose_simulator, :worker, :cycle],
      %{session_count: 2, ok: 1, errors: 0, completed: 1, timeouts: 0, duration_ms: 5},
      %{partition: 0, player_id: "player-prom-test"}
    )

    FirehoseSimulator.Metrics.emit_active_sessions()

    body =
      conn(:get, "/metrics")
      |> PrometheusExporter.call(PrometheusExporter.init([]))
      |> Map.fetch!(:resp_body)

    assert body =~ "firehose_simulator_event_feeder_posts_dispatch_events_dispatched"
    assert body =~ "firehose_simulator_event_feeder_posts_complete_ok"
    assert body =~ "firehose_simulator_event_feeder_posts_complete_error"
    assert body =~ "firehose_simulator_event_feeder_follows_dispatch_events_dispatched"
    assert body =~ "firehose_simulator_event_feeder_follows_complete_ok"
    assert body =~ "firehose_simulator_worker_query_count"
    assert body =~ "firehose_simulator_worker_cycle_count"

    assert body =~
             ~s(firehose_simulator_worker_query_lag_ms_bucket{kind="session_request",le="50"})

    assert body =~ "firehose_simulator_worker_query_lag_ms_count"
    assert body =~ "firehose_simulator_worker_query_latency_ms_bucket"
    assert body =~ "firehose_simulator_worker_cycle_duration_ms_bucket"

    assert body =~ "firehose_simulator_active_sessions_count"
  end
end
