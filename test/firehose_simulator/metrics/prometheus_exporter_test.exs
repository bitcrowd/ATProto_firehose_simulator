defmodule FirehoseSimulator.Metrics.PrometheusExporterTest do
  use ExUnit.Case, async: false

  import Plug.Test

  alias FirehoseSimulator.Metrics
  alias FirehoseSimulator.Metrics.PrometheusExporter

  test "exports metrics in prometheus text format" do
    before_snapshot = Metrics.snapshot()

    :telemetry.execute(
      [:firehose_simulator, :json, :file, :loaded],
      %{count: 1},
      %{path: "/tmp/scenario.json", kind: "scenario"}
    )

    :telemetry.execute(
      [:firehose_simulator, :player, :load],
      %{count: 1},
      %{player_id: "player-1", scenario_id: nil, schedulers: 1}
    )

    :telemetry.execute(
      [:firehose_simulator, :player, :start],
      %{count: 1},
      %{player_id: "player-1", from_state: :loaded}
    )

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
      [:firehose_simulator, :event_feeder, :inject],
      %{sessions_started: 4},
      %{player_id: "player-1", elapsed_ms: 10}
    )

    :telemetry.execute(
      [:firehose_simulator, :worker, :cycle],
      %{session_count: 4, ok: 1, errors: 0, completed: 1, timeouts: 0, duration_ms: 5},
      %{partition: 0, player_id: "player-1"}
    )

    :telemetry.execute(
      [:firehose_simulator, :player, :pause],
      %{count: 1},
      %{player_id: "player-1"}
    )

    snapshot =
      await_snapshot(fn current ->
        current.json_files_loaded >= 1 and
          current.player_pause >= 1 and current.active_sessions_total >= 3
      end)

    conn = conn(:get, "/metrics")
    conn = PrometheusExporter.call(conn, PrometheusExporter.init([]))
    body = conn.resp_body

    assert conn.status == 200
    assert ["text/plain; charset=utf-8"] = Plug.Conn.get_resp_header(conn, "content-type")

    assert snapshot.json_files_loaded == before_snapshot.json_files_loaded + 1
    assert snapshot.player_load == before_snapshot.player_load + 1
    assert snapshot.player_start == before_snapshot.player_start + 1
    assert snapshot.player_pause == before_snapshot.player_pause + 1

    assert body =~ "firehose_simulator_json_files_loaded_total #{snapshot.json_files_loaded}"
    assert body =~ "firehose_simulator_player_load_total #{snapshot.player_load}"
    assert body =~ "firehose_simulator_player_start_total #{snapshot.player_start}"
    assert body =~ "firehose_simulator_player_pause_total #{snapshot.player_pause}"
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
    assert body =~ "firehose_simulator_active_sessions #{snapshot.active_sessions_total}"
    assert body =~ "firehose_simulator_player_active_sessions{player_id=\"player-1\"} 3"
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
