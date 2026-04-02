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
    assert {:ok, %{"posts" => posts, "sessions" => nil, "follows" => nil}} = Jason.decode(content)
    assert is_list(posts)

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

  test "simulation liveview selects plan and controls playback", %{conn: conn} do
    :ok =
      State.put_simulation_plan("plan-1", %SimulationPlan{
        posts: [%{offset_ms: 10, user_id: 1}],
        sessions: nil,
        follows: nil
      })

    {:ok, view, _html} = live(conn, ~p"/simulation")

    refute has_element?(view, "#play-button[disabled]")
    assert has_element?(view, "#plan-status", "Selected plan: plan-1")

    view
    |> element("#simulation-select-plan-1")
    |> render_click()

    refute has_element?(view, "#play-button[disabled]")

    view
    |> form("#simulation-play-form", %{"play" => %{"offset_ms" => "250"}})
    |> render_submit()

    assert render(view) =~ "Simulation started."

    view |> element("#stop-button") |> render_click()
    assert render(view) =~ "Simulation stopped."

    view |> element("#reset-button") |> render_click()
    assert render(view) =~ "Simulation reset."
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

    def play(%SimulationPlan{posts: [%{offset_ms: 260, user_id: 1}]}, _opts),
      do: {:ok, %{started?: true}}

    def play(%SimulationPlan{posts: [%{offset_ms: 10, user_id: 1}]}, _opts),
      do: {:ok, %{started?: true}}

    def play(%SimulationPlan{}, _opts), do: {:error, :invalid_shift}
    def stop, do: :ok
    def reset, do: :ok
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
        "n": 10,
        "max_active_user_id": 5,
        "seed": 1,
        "time_units": 1,
        "tiers": [
          {"max_followers": 1000, "posts_per_day": 0.25}
        ]
      },
      "sessions_params": {
        "n": 10,
        "max_active_user_id": 5,
        "seed": 1,
        "time_units": 1,
        "tiers": [
          {"max_followers": 1000, "session_minutes": 240}
        ]
      },
      "follows_params": {
        "n": 10,
        "max_active_user_id": 5,
        "seed": 1,
        "time_units": 1,
        "tiers": [
          {"max_followers": 1000, "follows_per_day": 0.25}
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
      ]
    }
    """
  end
end
