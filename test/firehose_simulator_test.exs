defmodule FirehoseSimulatorTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias FirehoseSimulator.DatabaseConnection
  alias FirehoseSimulator.Player
  alias FirehoseSimulator.SimulationPlan

  setup do
    :ok = FirehoseSimulator.stop_all()
    :ok = FirehoseSimulator.State.clear_running_players()

    on_exit(fn ->
      :ok = FirehoseSimulator.stop_all()
      :ok = FirehoseSimulator.State.clear_running_players()
    end)

    :ok
  end

  describe "generate_simulation_plan_from_json/1" do
    @tag :tmp_dir
    test "loads simulation plan params json through the top-level api", %{tmp_dir: tmp_dir} do
      params_path =
        write_file!(
          tmp_dir,
          "simulation-plan-params",
          """
          {
            "seed": 1,
            "time_units": 1,
            "posts_params": {
              "num_users": 10,
              "max_active_user_id": 5,
              "tiers": [
                {"max_followers": 1000, "posts_per_time_unit": 0.25}
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
        _ = FirehoseSimulator.stop_all()
      end)

      :ok
    end

    test "starts playing and returns a player id" do
      simulation_plan = %SimulationPlan{sessions: nil, posts: nil, follows: nil}

      capture_log(fn ->
        assert {:ok, player_id, %{started?: true}} =
                 FirehoseSimulator.play(simulation_plan, scheduler_count: 1)

        assert is_binary(player_id)
      end)

      running_players = FirehoseSimulator.State.list_running_players()
      [player_id] = Map.keys(running_players)
      status = Player.status(player_id)
      assert status.running?
      assert status.loaded?
      assert status.feeder.started?
    end

    test "allows concurrent players for the same plan and stops them independently" do
      simulation_plan = %SimulationPlan{sessions: nil, posts: nil, follows: nil}

      capture_log(fn ->
        assert {:ok, player_1, _meta_1} =
                 FirehoseSimulator.play(simulation_plan, scheduler_count: 1)

        assert {:ok, player_2, _meta_2} =
                 FirehoseSimulator.play(simulation_plan, scheduler_count: 1)

        refute player_1 == player_2

        assert :ok = FirehoseSimulator.stop(player_1)

        status_2 = Player.status(player_2)
        assert status_2.running?
      end)
    end
  end

  describe "play_with_offset/3" do
    setup do
      on_exit(fn ->
        _ = FirehoseSimulator.stop_all()
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
        assert {:ok, player_id, %{started?: true}} =
                 FirehoseSimulator.play_with_offset(simulation_plan, 250, scheduler_count: 1)

        assert is_binary(player_id)
      end)

      running_players = FirehoseSimulator.State.list_running_players()
      [player_id] = Map.keys(running_players)
      status = Player.status(player_id)
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

    test "state defaults db connection string from DATABASE_URL" do
      previous_database_url = System.get_env("DATABASE_URL")
      test_database_url = "postgres://postgres:postgres@localhost:5432/state_default_test"

      on_exit(fn ->
        restore_env("DATABASE_URL", previous_database_url)
        :ok = FirehoseSimulator.State.reset_all()
      end)

      System.put_env("DATABASE_URL", test_database_url)
      assert :ok = FirehoseSimulator.State.reset_all()

      assert %DatabaseConnection{connection_string: ^test_database_url} =
               DatabaseConnection.default()

      assert test_database_url == FirehoseSimulator.State.get_db_connection_string()
    end
  end

  describe "export_userbase_to_csv/2" do
    @tag :tmp_dir
    test "exports a userbase json through the top-level api", %{tmp_dir: tmp_dir} do
      userbase_path =
        write_file!(
          tmp_dir,
          "userbase",
          """
          {
            "name": "csv export",
            "num_users": 4,
            "max_active_user_id": 4,
            "follower_density": 1.0
          }
          """
        )

      capture_log(fn ->
        assert {:ok, result} = FirehoseSimulator.export_userbase_to_csv(userbase_path, tmp_dir)
        assert File.exists?(result.meta_path)
        assert File.exists?(result.actor_csv_path)
        assert File.exists?(result.follow_csv_path)
      end)
    end
  end

  describe "import_userbase_from_csv/2" do
    test "returns manifest file errors before attempting database work" do
      connection = %DatabaseConnection{connection_string: "postgres://example"}

      capture_log(fn ->
        assert {:error, "cannot read userbase meta file at missing-userbase-meta.json"} =
                 FirehoseSimulator.import_userbase_from_csv(
                   "missing-userbase-meta.json",
                   connection
                 )
      end)
    end

    test "accepts a connection string through the top-level api" do
      capture_log(fn ->
        assert {:error, "cannot read userbase meta file at missing-userbase-meta.json"} =
                 FirehoseSimulator.import_userbase_from_csv(
                   "missing-userbase-meta.json",
                   "postgres://example"
                 )
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

  describe "reset/1 and reset/0" do
    test "resets an individual player and keeps others running" do
      simulation_plan = %SimulationPlan{sessions: nil, posts: nil, follows: nil}

      assert {:ok, player_1, _meta_1} =
               FirehoseSimulator.play(simulation_plan, scheduler_count: 1)

      assert {:ok, player_2, _meta_2} =
               FirehoseSimulator.play(simulation_plan, scheduler_count: 1)

      assert :ok = FirehoseSimulator.reset(player_1)

      assert Player.status(player_2).running?
      refute Map.has_key?(FirehoseSimulator.State.list_running_players(), player_1)
    end

    test "exposes global reset from the top-level api" do
      assert :ok = FirehoseSimulator.reset_all()
      assert :ok = FirehoseSimulator.reset()
    end
  end

  describe "shift_simulation_plan/2" do
    test "shifts offsets for all plan sections" do
      simulation_plan = %SimulationPlan{
        posts: [%{offset_ms: 10, user_id: 1}],
        sessions: [%{offset_ms: 20, user_id: 2, duration_ms: 30_000}],
        follows: [%{offset_ms: 30, actor_id: 2, subject_id: 1}],
        request_interval_ms: 15_000
      }

      shifted = FirehoseSimulator.shift_simulation_plan(simulation_plan, 250)

      assert shifted.posts == [%{offset_ms: 260, user_id: 1}]
      assert shifted.sessions == [%{offset_ms: 270, user_id: 2, duration_ms: 30_000}]
      assert shifted.follows == [%{offset_ms: 280, actor_id: 2, subject_id: 1}]
      assert shifted.request_interval_ms == 15_000
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

  defp restore_env(var, nil), do: System.delete_env(var)
  defp restore_env(var, value), do: System.put_env(var, value)
end
