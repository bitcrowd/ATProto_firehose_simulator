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

  test "simulation liveview creates plan and controls playback", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/simulation")

    assert has_element?(view, "#play-button[disabled]")

    simulation_plan_params_upload =
      file_input(view, "#simulation-plan-form", :simulation_plan_params_json, [
        %{
          name: "simulation_plan_params.json",
          content: simulation_plan_params_json(),
          type: "application/json"
        }
      ])

    render_upload(simulation_plan_params_upload, "simulation_plan_params.json")

    view
    |> form("#simulation-plan-form", %{"simulation" => %{"time_offset_ms" => "250"}})
    |> render_submit()

    assert has_element?(view, "#plan-status", "Simulation plan is loaded and ready to play.")

    view |> element("#play-button") |> render_click()
    assert render(view) =~ "Simulation started."

    view |> element("#stop-button") |> render_click()
    assert render(view) =~ "Simulation stopped."

    view |> element("#reset-button") |> render_click()
    assert has_element?(view, "#play-button[disabled]")
    assert render(view) =~ "Simulation reset."
  end

  test "simulation liveview defaults empty offset to zero", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/simulation")

    simulation_plan_params_upload =
      file_input(view, "#simulation-plan-form", :simulation_plan_params_json, [
        %{
          name: "simulation_plan_params.json",
          content: simulation_plan_params_json(),
          type: "application/json"
        }
      ])

    render_upload(simulation_plan_params_upload, "simulation_plan_params.json")

    view
    |> form("#simulation-plan-form", %{"simulation" => %{"time_offset_ms" => ""}})
    |> render_submit()

    assert has_element?(view, "#plan-status", "Simulation plan is loaded and ready to play.")
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

    def load_simulation_plan_from_json(paths) do
      if is_binary(Keyword.get(paths, :simulation_plan_params)) and
           File.exists?(Keyword.fetch!(paths, :simulation_plan_params)) do
        {:ok, %SimulationPlan{posts: [%{offset_ms: 10, user_id: 1}], sessions: nil, follows: nil}}
      else
        {:error, "invalid simulation plan paths"}
      end
    end

    def shift_simulation_plan(%SimulationPlan{} = simulation_plan, offset_ms) do
      FirehoseSimulator.shift_simulation_plan(simulation_plan, offset_ms)
    end

    def play(%SimulationPlan{} = simulation_plan), do: play(simulation_plan, [])

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
end
