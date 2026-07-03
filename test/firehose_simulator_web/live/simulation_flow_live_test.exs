defmodule FirehoseSimulatorWeb.SimulationFlowLiveTest do
  use FirehoseSimulatorWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias FirehoseSimulator.Scenario
  alias FirehoseSimulator.SimulationPlan
  alias FirehoseSimulator.SimulationPlan.Entry
  alias FirehoseSimulator.State

  @moduletag :tmp_dir

  setup do
    clear_test_state()

    on_exit(fn ->
      clear_test_state()
    end)

    :ok
  end

  test "setup liveview requires an uploaded userbase file", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/setup")
    refute has_element?(view, "#setup-db-connection-string")
    refute has_element?(view, "#setup-import-db-connection-string")

    view
    |> form("#setup-form", %{"generate" => %{}})
    |> render_submit()

    assert render(view) =~ "Please upload userbase JSON first"
    refute has_element?(view, "#setup-result")
  end

  test "setup liveview requires an uploaded manifest file", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/setup")

    view
    |> form("#setup-import-form", %{"import" => %{}})
    |> render_submit()

    assert render(view) =~ "Please upload userbase meta JSON first"
    refute has_element?(view, "#setup-result")
  end

  test "planning liveview generates and imports scenarios", %{conn: conn, tmp_dir: tmp_dir} do
    {:ok, view, _html} = live(conn, ~p"/planning")

    params_upload =
      file_input(view, "#planning-generate-form", :scenario_params_json, [
        %{
          name: "scenario_params.json",
          content: scenario_params_json(),
          type: "application/json"
        }
      ])

    render_upload(params_upload, "scenario_params.json")

    view
    |> form("#planning-generate-form", %{"generate" => %{"scenario_name" => "generated-a"}})
    |> render_submit()

    generated_scenario_id =
      State.list_scenarios()
      |> Map.keys()
      |> Enum.find(&String.starts_with?(&1, "generated-a"))

    assert generated_scenario_id
    assert has_element?(view, "#scenario-row-#{generated_scenario_id}")

    view
    |> element("#export-scenario-#{generated_scenario_id}")
    |> render_click()

    assert_push_event(view, "save_scenario_json", %{filename: filename, content: content})
    assert filename == "#{generated_scenario_id}.json"

    assert {:ok,
            %{
              "posts" => posts,
              "sessions" => sessions,
              "follows" => follows,
              "request_interval_ms" => request_interval_ms,
              "timeline_limit" => timeline_limit
            }} = Jason.decode(content)

    assert is_list(posts)
    assert is_list(sessions)
    assert is_list(follows)
    assert request_interval_ms == 25_000
    assert timeline_limit == 40

    import_upload =
      file_input(view, "#planning-import-form", :scenario_json, [
        %{
          name: "import-plan.json",
          content: scenario_json(),
          type: "application/json"
        }
      ])

    render_upload(import_upload, "import-plan.json")

    view
    |> form("#planning-import-form", %{"import" => %{"scenario_name" => "imported-b"}})
    |> render_submit()

    imported_scenario_id =
      State.list_scenarios()
      |> Map.keys()
      |> Enum.find(&String.starts_with?(&1, "imported-b"))

    assert imported_scenario_id
    assert has_element?(view, "#scenario-row-#{imported_scenario_id}")

    scenario_path = write_runtime_file!(tmp_dir, "live-plan-scenario", scenario_json())

    plan_upload =
      file_input(view, "#planning-import-plan-form", :simulation_plan_json, [
        %{
          name: "simulation-plan.json",
          content: simulation_plan_json(scenario_path),
          type: "application/json"
        }
      ])

    render_upload(plan_upload, "simulation-plan.json")

    view
    |> form("#planning-import-plan-form", %{"import_plan" => %{}})
    |> render_submit()

    assert %SimulationPlan{entries: [%Entry{scenario_name: "imported-plan"}]} =
             State.get_simulation_plan()

    refute has_element?(view, "#scenario-row-imported-plan")
  end

  test "vacuum liveview runs selected vacuum actions", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/vacuum")

    assert has_element?(view, ~s(a[href="/vacuum"]), "Vacuum")
    refute has_element?(view, "#vacuum-db-connection-string")

    view
    |> form("#vacuum-form", %{"vacuum" => %{}})
    |> render_submit()

    assert render(view) =~ "Select at least one vacuum action"
    refute has_element?(view, "#vacuum-result")
  end

  test "simulation liveview selects scenario and controls lifecycle", %{conn: conn} do
    :ok =
      State.put_scenario("plan-1", %Scenario{
        posts: [%{offset_ms: 10, user_id: 1}],
        sessions: nil,
        follows: nil
      })

    {:ok, view, _html} = live(conn, ~p"/simulation")

    assert has_element?(view, "#load-button[disabled]")
    assert has_element?(view, "#simulation-scenario-summary-plan-1")
    assert has_element?(view, "#simulation-plan-empty")

    view
    |> element("#simulation-select-plan-1")
    |> render_click()

    assert_patch(view, ~p"/simulation?scenario_id=plan-1")
    refute has_element?(view, "#load-button[disabled]")

    view
    |> form("#simulation-load-form", %{"load" => %{"offset_ms" => "250"}})
    |> render_submit()

    [player_id] = State.list_players() |> Map.keys()

    assert render(view) =~ "Simulation loaded for #{player_id}."
    assert has_element?(view, "#player-#{player_id}")
    assert has_element?(view, "#player-state-#{player_id}", "loaded")

    view
    |> element("#start-player-#{player_id}")
    |> render_click()

    assert render(view) =~ "Simulation started for #{player_id}."
    assert has_element?(view, "#player-state-#{player_id}", "running")
    assert has_element?(view, "#simulation-plan-entry-count")

    view
    |> element("#pause-player-#{player_id}")
    |> render_click()

    assert render(view) =~ "Simulation paused for #{player_id}."
    assert has_element?(view, "#player-state-#{player_id}", "paused")

    view
    |> form("#simulation-load-form", %{"load" => %{"offset_ms" => "250"}})
    |> render_submit()

    player_ids = State.list_players() |> Map.keys() |> Enum.sort()
    assert [_, _] = player_ids
    second_player_id = Enum.find(player_ids, &(&1 != player_id))
    assert has_element?(view, "#player-#{second_player_id}")

    view |> element("#start-player-#{player_id}") |> render_click()
    assert has_element?(view, "#player-state-#{player_id}", "running")

    assert %SimulationPlan{entries: [%Entry{offset_ms: 250}, %Entry{offset_ms: 250}]} =
             State.get_simulation_plan()

    view |> element("#stop-player-#{player_id}") |> render_click()
    assert render(view) =~ "Simulation stopped for #{player_id}."

    view |> element("#stop-all-button") |> render_click()
    assert render(view) =~ "All simulation players stopped."
  end

  test "simulation liveview ignores missing selected scenario in url", %{conn: conn} do
    :ok =
      State.put_scenario("plan-1", %Scenario{
        posts: [%{offset_ms: 10, user_id: 1}],
        sessions: nil,
        follows: nil
      })

    {:ok, view, _html} = live(conn, ~p"/simulation?scenario_id=missing-plan")

    assert has_element?(view, "#simulation-scenario-summary-plan-1")
    assert has_element?(view, "#load-button[disabled]")
  end

  test "metrics liveview renders metrics tab and counters", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/metrics")

    assert has_element?(view, ~s(a[href="/metrics"]), "Metrics")
    assert has_element?(view, "#metric-event-feeder-inject-count")
    assert has_element?(view, "#metric-worker-window-query-count")
    assert has_element?(view, "#metric-worker-window-avg-latency-ms")
    assert has_element?(view, "#metric-worker-window-p95-latency-ms")
    assert has_element?(view, "#metric-worker-window-avg-lag-ms")
    assert has_element?(view, "#metric-worker-window-p95-lag-ms")
    assert has_element?(view, "#metric-worker-window-max-lag-ms")
    assert has_element?(view, "#metric-worker-window-error-rate")
    assert has_element?(view, "#metric-worker-window-timeout-rate")
    assert has_element?(view, "#metric-worker-cycle-count")
  end

  defp scenario_params_json do
    """
    {
      "seed": 1,
      "time_units": 1,
      "posts_params": {
        "num_users": 10,
        "max_active_user_id": 5,
        "follower_density": 2.0,
        "tiers": [
          {"max_followers": 1000, "posts_per_time_unit": 0.25}
        ]
      },
      "sessions_params": {
        "num_users": 10,
        "max_active_user_id": 5,
        "follower_density": 2.0,
        "request_interval_ms": 25000,
        "timeline_limit": 40,
        "tiers": [
          {"max_followers": 1000, "session_minutes": 240}
        ]
      },
      "follows_params": {
        "num_users": 10,
        "max_active_user_id": 5,
        "follower_density": 2.0,
        "tiers": [
          {"max_followers": 1000, "follows_per_time_unit": 0.25}
        ]
      }
    }
    """
  end

  defp scenario_json do
    """
    {
      "posts": [
        {"offset_ms": 30, "user_id": 3}
      ],
      "sessions": [
        {"offset_ms": 40, "user_id": 3, "duration_ms": 120000}
      ],
      "follows": [
        {"offset_ms": 50, "actor_id": 3, "subject_id": 1}
      ],
      "request_interval_ms": 35000,
      "timeline_limit": 28
    }
    """
  end

  defp simulation_plan_json(scenario_path) do
    """
    {
      "entries": [
        {
          "scenario_name": "imported-plan",
          "scenario_path": "#{scenario_path}",
          "offset_ms": 0
        }
      ]
    }
    """
  end

  defp write_runtime_file!(tmp_dir, prefix, content) do
    path =
      Path.join(
        tmp_dir,
        "#{prefix}-#{System.unique_integer([:positive, :monotonic])}.json"
      )

    File.write!(path, content)
    path
  end

  defp clear_test_state do
    {:ok, simulation_plan} = SimulationPlan.new(%{entries: []})
    :ok = FirehoseSimulator.stop()
    :ok = State.clear_scenarios()
    :ok = State.clear_players()
    :ok = State.put_simulation_plan(simulation_plan)
    :ok = State.put_userbase_result(false, nil)
    :ok
  end
end
