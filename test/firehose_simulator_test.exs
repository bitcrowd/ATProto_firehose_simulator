defmodule FirehoseSimulatorTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias FirehoseSimulator.DatabaseConnection
  alias FirehoseSimulator.Player
  alias FirehoseSimulator.SimulationPlan

  describe "generate_simulation_plan_from_json/1" do
    @tag :tmp_dir
    test "loads simulation plan params json through the top-level api", %{tmp_dir: tmp_dir} do
      params_path =
        write_file!(
          tmp_dir,
          "simulation-plan-params",
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
            }
          }
          """
        )

      capture_log(fn ->
        send(
          self(),
          {:result,
           FirehoseSimulator.generate_simulation_plan_from_json(
             simulation_plan_params: params_path
           )}
        )
      end)

      assert_receive {:result, {:ok, %SimulationPlan{posts: posts}}}
      assert is_list(posts)
    end
  end

  describe "import_simulation_plan_from_json/1 + export_simulation_plan_to_json/2" do
    @tag :tmp_dir
    test "imports and exports full simulation plan json", %{tmp_dir: tmp_dir} do
      input_path =
        write_file!(
          tmp_dir,
          "simulation-plan",
          """
          {
            "posts": [{"offset_ms": 10, "user_id": 1}],
            "sessions": [{"offset_ms": 20, "user_id": 2, "duration_ms": 30000}],
            "follows": [{"offset_ms": 30, "actor_id": 2, "subject_id": 1}]
          }
          """
        )

      assert {:ok, %SimulationPlan{} = simulation_plan} =
               FirehoseSimulator.import_simulation_plan_from_json(input_path)

      output_path = Path.join(tmp_dir, "exported-plan.json")
      assert :ok = FirehoseSimulator.export_simulation_plan_to_json(simulation_plan, output_path)
      assert File.exists?(output_path)

      assert {:ok, %SimulationPlan{} = reloaded} =
               FirehoseSimulator.import_simulation_plan_from_json(output_path)

      assert reloaded == simulation_plan
    end
  end

  describe "play/2" do
    setup do
      on_exit(fn ->
        _ = Player.stop()
      end)

      :ok
    end

    test "starts playing immediately with an in-memory simulation plan" do
      simulation_plan = %SimulationPlan{sessions: nil, posts: nil, follows: nil}

      capture_log(fn ->
        assert {:ok, %{started?: true}} =
                 FirehoseSimulator.play(simulation_plan, scheduler_count: 1)
      end)

      _ = :sys.get_state(FirehoseSimulator.SimulationPlan.EventFeeder)

      status = Player.status()
      assert status.running?
      assert status.loaded?
      assert status.feeder.started?
    end
  end

  describe "play_with_offset/3" do
    setup do
      on_exit(fn ->
        _ = Player.stop()
      end)

      :ok
    end

    test "shifts the plan before starting playback" do
      simulation_plan = %SimulationPlan{
        posts: [%{offset_ms: 10, user_id: 1}],
        sessions: nil,
        follows: nil
      }

      capture_log(fn ->
        assert {:ok, %{started?: true}} =
                 FirehoseSimulator.play_with_offset(simulation_plan, 250, scheduler_count: 1)
      end)

      _ = :sys.get_state(FirehoseSimulator.SimulationPlan.EventFeeder)

      status = Player.status()
      assert status.running?
      assert status.loaded?
      assert status.feeder.started?
    end
  end

  describe "create_userbase/2" do
    test "returns file load errors before attempting database work" do
      connection = %DatabaseConnection{connection_string: "postgres://example"}

      capture_log(fn ->
        assert {:error, "cannot read userbase file at missing-userbase.json"} =
                 FirehoseSimulator.create_userbase("missing-userbase.json", connection)
      end)
    end

    test "accepts a connection string through the top-level api" do
      capture_log(fn ->
        assert {:error, "cannot read userbase file at missing-userbase.json"} =
                 FirehoseSimulator.create_userbase("missing-userbase.json", "postgres://example")
      end)
    end
  end

  describe "bulk_create_simulation_plan/2" do
    test "returns connection validation errors before attempting database work" do
      connection = %DatabaseConnection{connection_string: "not-a-url"}

      simulation_plan = %SimulationPlan{
        posts: [%{offset_ms: 25, user_id: 1}],
        sessions: nil,
        follows: nil
      }

      capture_log(fn ->
        assert {:error, "Connection string must be a postgres URL"} =
                 FirehoseSimulator.bulk_create_simulation_plan(simulation_plan, connection)
      end)
    end
  end

  describe "vacuum/2" do
    test "returns action validation errors" do
      capture_log(fn ->
        assert {:error, "Select at least one vacuum action"} =
                 FirehoseSimulator.vacuum("postgres://example", [])
      end)
    end

    test "returns connection validation errors before attempting database work" do
      capture_log(fn ->
        assert {:error, "Connection string must be a postgres URL"} =
                 FirehoseSimulator.vacuum("not-a-url", delete_userbase?: true)
      end)
    end
  end

  describe "reset/0" do
    test "exposes player reset from the top-level api" do
      assert :ok = FirehoseSimulator.reset()
    end
  end

  describe "shift_simulation_plan/2" do
    test "shifts offsets for all plan sections" do
      simulation_plan = %SimulationPlan{
        posts: [%{offset_ms: 10, user_id: 1}],
        sessions: [%{offset_ms: 20, user_id: 2, duration_ms: 30_000}],
        follows: [%{offset_ms: 30, actor_id: 2, subject_id: 1}]
      }

      shifted = FirehoseSimulator.shift_simulation_plan(simulation_plan, 250)

      assert shifted.posts == [%{offset_ms: 260, user_id: 1}]
      assert shifted.sessions == [%{offset_ms: 270, user_id: 2, duration_ms: 30_000}]
      assert shifted.follows == [%{offset_ms: 280, actor_id: 2, subject_id: 1}]
    end

    test "keeps nil sections unchanged" do
      simulation_plan = %SimulationPlan{posts: nil, sessions: nil, follows: nil}

      assert %SimulationPlan{posts: nil, sessions: nil, follows: nil} =
               FirehoseSimulator.shift_simulation_plan(simulation_plan, 123)
    end
  end

  defp write_file!(tmp_dir, prefix, content) do
    path = Path.join(tmp_dir, "#{prefix}-#{System.unique_integer([:positive])}.json")
    File.write!(path, content)
    path
  end
end
