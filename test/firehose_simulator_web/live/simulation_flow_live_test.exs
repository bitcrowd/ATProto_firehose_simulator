defmodule FirehoseSimulatorWeb.SimulationFlowLiveTest do
  use FirehoseSimulatorWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias FirehoseSimulator.SimulationPlan
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
    assert has_element?(view, "#setup-db-connection-string")

    upload =
      file_input(view, "#setup-form", :userbase, [
        %{name: "userbase.json", content: userbase_json(), type: "application/json"}
      ])

    render_upload(upload, "userbase.json")

    view
    |> form("#setup-form", %{"setup" => %{"db_connection_string" => "postgres://example"}})
    |> render_submit()

    assert has_element?(view, "#setup-result")
    assert render(view) =~ "Userbase created successfully."
  end

  test "planning liveview generates and imports plans", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/planning")

    params_upload =
      file_input(view, "#planning-generate-form", :simulation_plan_params_json, [
        %{
          name: "simulation_plan_params.json",
          content: simulation_plan_params_json(),
          type: "application/json"
        }
      ])

    render_upload(params_upload, "simulation_plan_params.json")

    view
    |> form("#planning-generate-form", %{"generate" => %{"plan_name" => "generated-a"}})
    |> render_submit()

    generated_plan_id =
      State.list_simulation_plans()
      |> Map.keys()
      |> Enum.find(&String.starts_with?(&1, "generated-a"))

    assert generated_plan_id
    assert has_element?(view, "#plan-row-#{generated_plan_id}")

    view
    |> element("#export-plan-#{generated_plan_id}")
    |> render_click()

    assert_push_event(view, "save_simulation_plan_json", %{filename: filename, content: content})
    assert filename == "#{generated_plan_id}.json"

    assert {:ok,
            %{
              "posts" => posts,
              "sessions" => nil,
              "follows" => nil,
              "request_interval_ms" => request_interval_ms
            }} = Jason.decode(content)

    assert is_list(posts)
    assert request_interval_ms == 30_000

    import_upload =
      file_input(view, "#planning-import-form", :simulation_plan_json, [
        %{
          name: "import-plan.json",
          content: simulation_plan_json(),
          type: "application/json"
        }
      ])

    render_upload(import_upload, "import-plan.json")

    view
    |> form("#planning-import-form", %{"import" => %{"plan_name" => "imported-b"}})
    |> render_submit()

    imported_plan_id =
      State.list_simulation_plans()
      |> Map.keys()
      |> Enum.find(&String.starts_with?(&1, "imported-b"))

    assert imported_plan_id
    assert has_element?(view, "#plan-row-#{imported_plan_id}")
  end

  test "vacuum liveview runs selected vacuum actions", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/vacuum")

    assert has_element?(view, ~s(a[href="/vacuum"]), "Vacuum")
    assert has_element?(view, "#vacuum-db-connection-string")

    view
    |> form("#vacuum-form", %{
      "vacuum" => %{
        "db_connection_string" => "postgres://example",
        "delete_userbase" => "true",
        "vacuum_posts" => "true"
      }
    })
    |> render_submit()

    assert has_element?(view, "#vacuum-result")
    assert render(view) =~ "Vacuum actions completed."
  end

  test "simulation liveview selects plan and controls playback", %{conn: conn} do
    :ok =
      State.put_simulation_plan("plan-1", %SimulationPlan{
        posts: [%{offset_ms: 10, user_id: 1}],
        sessions: nil,
        follows: nil
      })

    {:ok, view, _html} = live(conn, ~p"/simulation")

    refute has_element?(view, "#play-button[disabled]")
    assert has_element?(view, "#simulation-plan-summary-plan-1")

    view
    |> element("#simulation-select-plan-1")
    |> render_click()

    refute has_element?(view, "#play-button[disabled]")

    view
    |> form("#simulation-play-form", %{"play" => %{"offset_ms" => "250"}})
    |> render_submit()

    assert render(view) =~ "Simulation started for player-1."
    assert has_element?(view, "#running-player-player-1")

    view
    |> form("#simulation-play-form", %{"play" => %{"offset_ms" => "250"}})
    |> render_submit()

    assert has_element?(view, "#running-player-player-2")

    view |> element("#stop-player-player-1") |> render_click()
    assert render(view) =~ "Simulation stopped for player-1."

    view |> element("#reset-player-player-2") |> render_click()
    assert render(view) =~ "Simulation reset for player-2."

    view
    |> form("#simulation-play-form", %{"play" => %{"offset_ms" => "250"}})
    |> render_submit()

    assert has_element?(view, "#running-player-player-1")

    view |> element("#stop-all-button") |> render_click()
    assert render(view) =~ "All simulation players stopped."

    view |> element("#reset-all-button") |> render_click()
    assert render(view) =~ "All simulation players reset."
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

    def create_userbase(path, connection_string) do
      if File.exists?(path) and String.starts_with?(connection_string, "postgres://") do
        {:ok, %{userbase_path: path, db_connection_string: connection_string}}
      else
        {:error, "invalid setup inputs"}
      end
    end

    def generate_simulation_plan_from_json(paths) do
      if is_binary(Keyword.get(paths, :simulation_plan_params)) and
           File.exists?(Keyword.fetch!(paths, :simulation_plan_params)) do
        {:ok, %SimulationPlan{posts: [%{offset_ms: 10, user_id: 1}], sessions: nil, follows: nil}}
      else
        {:error, "invalid simulation plan paths"}
      end
    end

    def import_simulation_plan_from_json(path) do
      if File.exists?(path) do
        {:ok,
         %SimulationPlan{
           posts: [%{offset_ms: 20, user_id: 2}],
           sessions: [%{offset_ms: 25, user_id: 2, duration_ms: 30_000}],
           follows: nil
         }}
      else
        {:error, "invalid simulation plan path"}
      end
    end

    def shift_simulation_plan(%SimulationPlan{} = simulation_plan, offset_ms) do
      FirehoseSimulator.shift_simulation_plan(simulation_plan, offset_ms)
    end

    def play(%SimulationPlan{} = simulation_plan), do: play(simulation_plan, [])

    def play_with_offset(%SimulationPlan{} = simulation_plan, offset_ms)
        when is_integer(offset_ms) do
      simulation_plan
      |> FirehoseSimulator.shift_simulation_plan(offset_ms)
      |> play()
    end

    def play(%SimulationPlan{posts: [%{offset_ms: 260, user_id: 1}]}, _opts) do
      player_id = next_fake_player_id()
      metadata = %{player_id: player_id, started?: true}
      :ok = State.put_running_player(player_id, metadata)
      {:ok, player_id, metadata}
    end

    def play(%SimulationPlan{posts: [%{offset_ms: 10, user_id: 1}]}, _opts) do
      player_id = next_fake_player_id()
      metadata = %{player_id: player_id, started?: true}
      :ok = State.put_running_player(player_id, metadata)
      {:ok, player_id, metadata}
    end

    def play(%SimulationPlan{}, _opts), do: {:error, :invalid_shift}

    def stop(player_id) do
      :ok = State.delete_running_player(player_id)
      :ok
    end

    def reset(player_id) do
      :ok = State.delete_running_player(player_id)
      :ok
    end

    def reset_all do
      State.clear_running_players()
    end

    def stop_all do
      State.clear_running_players()
    end

    def vacuum(connection_string, opts) when is_binary(connection_string) do
      delete_userbase? = Keyword.get(opts, :delete_userbase?, false)
      vacuum_posts? = Keyword.get(opts, :vacuum_posts?, false)

      if String.starts_with?(connection_string, "postgres://") and
           (delete_userbase? or vacuum_posts?) do
        {:ok,
         %{
           delete_userbase?: delete_userbase?,
           vacuum_posts?: vacuum_posts?,
           deleted: %{actors: 10, posts: 20, follows: 30},
           vacuum: %{table: "bsky.post", mode: "full"}
         }}
      else
        {:error, "invalid vacuum inputs"}
      end
    end

    defp next_fake_player_id do
      count = map_size(State.list_running_players()) + 1
      "player-#{count}"
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

  defp simulation_plan_params_json do
    """
    {
      "posts_params": {
        "num_users": 10,
        "max_active_user_id": 5,
        "follower_density": 2.0,
        "seed": 1,
        "time_units": 1,
        "tiers": [
          {"max_followers": 1000, "posts_per_time_unit": 0.25}
        ]
      },
      "sessions_params": {
        "num_users": 10,
        "max_active_user_id": 5,
        "follower_density": 2.0,
        "seed": 1,
        "time_units": 1,
        "request_interval_ms": 25000,
        "tiers": [
          {"max_followers": 1000, "session_minutes": 240}
        ]
      },
      "follows_params": {
        "num_users": 10,
        "max_active_user_id": 5,
        "follower_density": 2.0,
        "seed": 1,
        "time_units": 1,
        "tiers": [
          {"max_followers": 1000, "follows_per_time_unit": 0.25}
        ]
      }
    }
    """
  end

  defp simulation_plan_json do
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
      "request_interval_ms": 35000
    }
    """
  end
end
