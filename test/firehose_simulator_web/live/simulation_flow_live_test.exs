defmodule FirehoseSimulatorWeb.SimulationFlowLiveTest do
  use FirehoseSimulatorWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias FirehoseSimulator.Scenario
  alias FirehoseSimulator.State

  setup do
    original_simulator = Application.get_env(:firehose_simulator, :simulator_module)
    Application.put_env(:firehose_simulator, :simulator_module, __MODULE__.FakeSimulator)
    :ok = State.reset_all()

    on_exit(fn ->
      if original_simulator do
        Application.put_env(:firehose_simulator, :simulator_module, original_simulator)
      else
        Application.delete_env(:firehose_simulator, :simulator_module)
      end

      :ok = State.reset_all()
    end)

    :ok
  end

  test "setup liveview uploads userbase and creates userbase", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/setup")
    refute has_element?(view, "#setup-db-connection-string")
    refute has_element?(view, "#setup-import-db-connection-string")

    upload =
      file_input(view, "#setup-form", :userbase, [
        %{name: "userbase.json", content: userbase_json(), type: "application/json"}
      ])

    render_upload(upload, "userbase.json")

    view
    |> form("#setup-form", %{"generate" => %{}})
    |> render_submit()

    assert has_element?(view, "#setup-result")
    assert render(view) =~ "Userbase created successfully."
  end

  test "setup liveview uploads manifest and imports userbase", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/setup")

    upload =
      file_input(view, "#setup-import-form", :userbase_meta, [
        %{name: "userbase_meta.json", content: userbase_meta_json(), type: "application/json"}
      ])

    render_upload(upload, "userbase_meta.json")

    view
    |> form("#setup-import-form", %{"import" => %{}})
    |> render_submit()

    assert has_element?(view, "#setup-result")
    assert render(view) =~ "Userbase imported successfully."
  end

  test "planning liveview generates and imports scenarios", %{conn: conn} do
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
              "sessions" => nil,
              "follows" => nil,
              "request_interval_ms" => request_interval_ms,
              "timeline_limit" => timeline_limit
            }} = Jason.decode(content)

    assert is_list(posts)
    assert request_interval_ms == 30_000
    assert timeline_limit == 20

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
  end

  test "vacuum liveview runs selected vacuum actions", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/vacuum")

    assert has_element?(view, ~s(a[href="/vacuum"]), "Vacuum")
    refute has_element?(view, "#vacuum-db-connection-string")

    view
    |> form("#vacuum-form", %{
      "vacuum" => %{
        "delete_userbase" => "true",
        "delete_posts" => "true"
      }
    })
    |> render_submit()

    assert has_element?(view, "#vacuum-result")
    assert render(view) =~ "Vacuum actions completed."
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

    view
    |> element("#simulation-select-plan-1")
    |> render_click()

    assert_patch(view, ~p"/simulation?scenario_id=plan-1")
    refute has_element?(view, "#load-button[disabled]")

    view
    |> form("#simulation-load-form", %{"load" => %{"offset_ms" => "250"}})
    |> render_submit()

    assert render(view) =~ "Simulation loaded for player-1."
    assert has_element?(view, "#player-player-1")
    assert has_element?(view, "#player-state-player-1", "loaded")

    view
    |> element("#start-player-player-1")
    |> render_click()

    assert render(view) =~ "Simulation started for player-1."
    assert has_element?(view, "#player-state-player-1", "running")

    view
    |> element("#pause-player-player-1")
    |> render_click()

    assert render(view) =~ "Simulation paused for player-1."
    assert has_element?(view, "#player-state-player-1", "paused")

    view
    |> form("#simulation-load-form", %{"load" => %{"offset_ms" => "250"}})
    |> render_submit()

    assert has_element?(view, "#player-player-2")

    view |> element("#start-player-player-1") |> render_click()
    assert has_element?(view, "#player-state-player-1", "running")

    view |> element("#stop-player-player-1") |> render_click()
    assert render(view) =~ "Simulation stopped for player-1."

    view |> element("#stop-all-button") |> render_click()
    assert render(view) =~ "All simulation players stopped."

    view |> element("#reset-all-button") |> render_click()
    assert render(view) =~ "All simulation players reset."
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
    assert has_element?(view, "#metric-worker-window-error-rate")
    assert has_element?(view, "#metric-worker-window-timeout-rate")
    assert has_element?(view, "#metric-worker-lifetime-query-count")
    assert has_element?(view, "#metric-worker-lifetime-avg-latency-ms")
    assert has_element?(view, "#metric-worker-cycle-count")
  end

  defmodule FakeSimulator do
    @moduledoc false

    def create_userbase(path) do
      if File.exists?(path), do: {:ok, %{userbase_path: path}}, else: {:error, "invalid setup"}
    end

    def import_userbase_from_csv(path) do
      if File.exists?(path),
        do: {:ok, %{userbase_meta_path: path}},
        else: {:error, "invalid import"}
    end

    def generate_scenario_from_json(paths) do
      if is_binary(Keyword.get(paths, :scenario_params)) and
           File.exists?(Keyword.fetch!(paths, :scenario_params)) do
        {:ok, %Scenario{posts: [%{offset_ms: 10, user_id: 1}], sessions: nil, follows: nil}}
      else
        {:error, "invalid scenario paths"}
      end
    end

    def import_scenario_from_json(path) do
      if File.exists?(path) do
        {:ok,
         %Scenario{
           posts: [%{offset_ms: 20, user_id: 2}],
           sessions: [%{offset_ms: 25, user_id: 2, duration_ms: 30_000}],
           follows: nil
         }}
      else
        {:error, "invalid scenario path"}
      end
    end

    def shift_scenario(%Scenario{} = scenario, offset_ms) do
      FirehoseSimulator.shift_scenario(scenario, offset_ms)
    end

    def load(%Scenario{} = scenario), do: load(scenario, [])

    def load_with_offset(%Scenario{} = scenario, offset_ms)
        when is_integer(offset_ms) do
      load_with_offset(scenario, offset_ms, [])
    end

    def load_with_offset(%Scenario{} = scenario, offset_ms, _opts)
        when is_integer(offset_ms) do
      scenario
      |> FirehoseSimulator.shift_scenario(offset_ms)
      |> load()
    end

    def load(%Scenario{posts: [%{offset_ms: 260, user_id: 1}]}, _opts) do
      player_id = next_fake_player_id()
      metadata = base_metadata(player_id, :loaded)
      :ok = State.put_player(player_id, metadata)
      {:ok, player_id, metadata}
    end

    def load(%Scenario{posts: [%{offset_ms: 10, user_id: 1}]}, _opts) do
      player_id = next_fake_player_id()
      metadata = base_metadata(player_id, :loaded)
      :ok = State.put_player(player_id, metadata)
      {:ok, player_id, metadata}
    end

    def load(%Scenario{}, _opts), do: {:error, :invalid_shift}

    def start(player_id) do
      update_player(player_id, fn metadata ->
        metadata
        |> Map.put(:lifecycle_state, :running)
        |> Map.put_new(:started_at, System.system_time(:millisecond))
        |> Map.put(:paused_at, nil)
      end)
    end

    def pause(player_id) do
      update_player(player_id, fn metadata ->
        metadata
        |> Map.put(:lifecycle_state, :paused)
        |> Map.put(:paused_at, System.system_time(:millisecond))
      end)
    end

    def stop(player_id) do
      :ok = State.delete_player(player_id)
      :ok
    end

    def reset_all do
      State.clear_players()
    end

    def stop_all do
      State.clear_players()
    end

    def vacuum(opts) when is_list(opts) do
      delete_userbase? = Keyword.get(opts, :delete_userbase?, false)
      delete_posts? = Keyword.get(opts, :delete_posts?, false)

      if delete_userbase? or delete_posts? do
        {:ok,
         %{
           delete_userbase?: delete_userbase?,
           delete_posts?: delete_posts?,
           deleted_userbase:
             if(delete_userbase?, do: %{tables: ["bsky.follow", "bsky.actor"]}, else: nil),
           deleted_posts:
             if(delete_posts?,
               do: %{tables: ["bsky.feed_item", "bsky.record", "bsky.post"]},
               else: nil
             )
         }}
      else
        {:error, "invalid vacuum"}
      end
    end

    defp next_fake_player_id do
      count = map_size(State.list_players()) + 1
      "player-#{count}"
    end

    defp update_player(player_id, fun) do
      metadata =
        State.list_players()
        |> Map.fetch!(player_id)
        |> fun.()

      State.put_player(player_id, metadata)
    end

    defp base_metadata(player_id, lifecycle_state) do
      %{
        player_id: player_id,
        scenario_id: "plan-1",
        lifecycle_state: lifecycle_state,
        request_interval_ms: 30_000,
        timeline_limit: 20,
        schedulers: 1,
        loaded_at: System.system_time(:millisecond),
        started_at: nil,
        paused_at: nil,
        total_paused: 0
      }
    end
  end

  defp userbase_json do
    """
    {
      "name": "from-live",
      "num_users": 100,
      "max_active_user_id": 10,
      "follower_density": 2.0
    }
    """
  end

  defp userbase_meta_json do
    """
    {
      "version": 1,
      "kind": "userbase",
      "run_id": "demo-run",
      "exported_at": "2025-01-01T00:00:00Z",
      "userbase": {
        "name": "demo",
        "num_users": 10,
        "max_active_user_id": 10,
        "follower_density": 1.0
      },
      "files": {
        "actor": {
          "path": "/tmp/actor.csv",
          "row_count": 10
        },
        "follow": {
          "path": "/tmp/follow.csv",
          "row_count": 20
        }
      }
    }
    """
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
end
