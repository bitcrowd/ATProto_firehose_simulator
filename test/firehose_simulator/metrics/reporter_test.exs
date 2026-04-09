defmodule FirehoseSimulator.Metrics.ReporterTest do
  use ExUnit.Case, async: false

  alias FirehoseSimulator.Metrics.Reporter

  setup do
    :ok = Reporter.reset()
    {:ok, _paths} = File.rm_rf("tmp/simulation_reports")

    on_exit(fn ->
      :ok = Reporter.reset()
      {:ok, _paths} = File.rm_rf("tmp/simulation_reports")
    end)

    :ok
  end

  test "finalize_run writes a report file with per-player counters and timeline" do
    player_id = "player-report-test-1"
    :ok = Reporter.start_run(player_id, %{player_id: player_id, simulation_plan_id: "plan-1"})

    :telemetry.execute(
      [:firehose_simulator, :event_feeder, :inject],
      %{sessions_started: 2, posts_ok: 3, posts_error: 1, follows_ok: 4, follows_error: 0},
      %{player_id: player_id}
    )

    :telemetry.execute(
      [:firehose_simulator, :worker, :query],
      %{latency_ms: 10, rows: 12},
      %{status: :ok, player_id: player_id}
    )

    :telemetry.execute(
      [:firehose_simulator, :worker, :cycle],
      %{session_count: 7, ok: 6, errors: 1, completed: 2, timeouts: 0, duration_ms: 9},
      %{partition: 0, player_id: player_id}
    )

    assert {:ok, report_path} = Reporter.finalize_run(player_id, :stop)
    assert File.exists?(report_path)

    assert {:ok, report_json} = File.read(report_path)
    assert {:ok, report} = Jason.decode(report_json)

    assert report["player_id"] == player_id
    assert report["reason"] == "stop"
    assert report["plan_id"] == "plan-1"
    assert report["summary"]["event_feeder_sessions_started"] == 2
    assert report["summary"]["event_feeder_posts_ok"] == 3
    assert report["summary"]["worker_query_total_count"] == 1
    assert report["summary"]["worker_query_rows"] == 12
    assert report["summary"]["worker_query_total_latency_ms"] == 10
    assert report["summary"]["worker_query_by_status"]["ok"] == 1
    assert report["summary"]["worker_cycle_count"] == 1
    assert report["summary"]["worker_cycle_by_partition"]["0"] == 1
    assert is_list(report["timeline"])
    assert length(report["timeline"]) >= 1
  end

  test "finalize_run is idempotent and returns same path on repeated calls" do
    player_id = "player-report-test-2"
    :ok = Reporter.start_run(player_id, %{player_id: player_id})

    assert {:ok, report_path_1} = Reporter.finalize_run(player_id, :reset)
    assert {:ok, report_path_2} = Reporter.finalize_run(player_id, :reset)
    assert report_path_1 == report_path_2
  end
end
