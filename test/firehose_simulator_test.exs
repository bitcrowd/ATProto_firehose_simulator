defmodule FirehoseSimulatorTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias FirehoseSimulator.Player
  alias FirehoseSimulator.Scenario

  setup do
    :ok = FirehoseSimulator.stop_all()
    :ok = FirehoseSimulator.State.clear_players()

    on_exit(fn ->
      :ok = FirehoseSimulator.stop_all()
      :ok = FirehoseSimulator.State.clear_players()
    end)

    :ok
  end

  describe "generate_scenario_from_json/1" do
    @tag :tmp_dir
    test "loads scenario params json through the top-level api", %{tmp_dir: tmp_dir} do
      params_path =
        write_file!(
          tmp_dir,
          "scenario-params",
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
          {:result, FirehoseSimulator.generate_scenario_from_json(scenario_params: params_path)}
        )
      end)

      assert_receive {:result, {:ok, %Scenario{posts: posts}}}
      assert is_list(posts)
    end
  end

  describe "import_scenario_from_json/1 + export_scenario_to_json/2" do
    @tag :tmp_dir
    test "imports and exports full scenario json", %{tmp_dir: tmp_dir} do
      input_path =
        write_file!(
          tmp_dir,
          "scenario",
          """
          {
            "posts": [{"offset_ms": 10, "user_id": 1}],
            "sessions": [{"offset_ms": 20, "user_id": 2, "duration_ms": 30000}],
            "follows": [{"offset_ms": 30, "actor_id": 2, "subject_id": 1}]
          }
          """
        )

      assert {:ok, %Scenario{} = scenario} =
               FirehoseSimulator.import_scenario_from_json(input_path)

      output_path = Path.join(tmp_dir, "exported-plan.json")
      assert :ok = FirehoseSimulator.export_scenario_to_json(scenario, output_path)
      assert File.exists?(output_path)

      assert {:ok, %Scenario{} = reloaded} =
               FirehoseSimulator.import_scenario_from_json(output_path)

      assert reloaded == scenario
    end
  end

  describe "load/start/pause/stop" do
    setup do
      on_exit(fn ->
        _ = FirehoseSimulator.stop_all()
      end)

      :ok
    end

    test "loads a player and starts it" do
      scenario = %Scenario{
        sessions: nil,
        posts: nil,
        follows: nil,
        request_interval_ms: 15_000,
        timeline_limit: 42
      }

      capture_log(fn ->
        assert {:ok, player_id, metadata} =
                 FirehoseSimulator.load(scenario, scheduler_count: 1)

        assert is_binary(player_id)
        assert metadata.request_interval_ms == 15_000
        assert metadata.timeline_limit == 42
        assert metadata.lifecycle_state == :loaded
      end)

      [player_id] = FirehoseSimulator.State.list_players() |> Map.keys()

      status = Player.status(player_id)
      refute status.running?
      assert status.loaded?

      assert :ok = FirehoseSimulator.start(player_id)
      assert Player.status(player_id).running?
    end

    test "pauses and resumes without changing started_at" do
      scenario = %Scenario{sessions: nil, posts: nil, follows: nil}

      assert {:ok, player_id, _metadata} = FirehoseSimulator.load(scenario, scheduler_count: 1)
      assert :ok = FirehoseSimulator.start(player_id)

      started_at = Player.status(player_id).metadata.started_at

      assert :ok = FirehoseSimulator.pause(player_id)
      paused_status = Player.status(player_id)
      assert paused_status.paused?
      assert paused_status.metadata.paused_at

      assert :ok = FirehoseSimulator.start(player_id)

      resumed_status = Player.status(player_id)
      assert resumed_status.running?
      assert resumed_status.metadata.started_at == started_at
      assert resumed_status.metadata.total_paused >= 0
    end

    test "allows concurrent players for the same plan and stops them independently" do
      scenario = %Scenario{sessions: nil, posts: nil, follows: nil}

      capture_log(fn ->
        assert {:ok, player_1, _meta_1} =
                 FirehoseSimulator.load(scenario, scheduler_count: 1)

        assert {:ok, player_2, _meta_2} =
                 FirehoseSimulator.load(scenario, scheduler_count: 1)

        refute player_1 == player_2
        assert :ok = FirehoseSimulator.start(player_1)
        assert :ok = FirehoseSimulator.start(player_2)

        assert :ok = FirehoseSimulator.stop(player_1)

        status_2 = Player.status(player_2)
        assert status_2.running?
      end)
    end
  end

  describe "load_with_offset/3" do
    setup do
      on_exit(fn ->
        _ = FirehoseSimulator.stop_all()
      end)

      :ok
    end

    test "shifts the plan before loading playback" do
      scenario = %Scenario{
        posts: [%{offset_ms: 10, user_id: 1}],
        sessions: nil,
        follows: nil
      }

      capture_log(fn ->
        assert {:ok, player_id, metadata} =
                 FirehoseSimulator.load_with_offset(scenario, 250, scheduler_count: 1)

        assert is_binary(player_id)
        assert metadata.lifecycle_state == :loaded
      end)

      [player_id] = FirehoseSimulator.State.list_players() |> Map.keys()
      status = Player.status(player_id)
      assert status.loaded?
      refute status.running?
    end
  end

  describe "create_userbase/1" do
    test "returns file load errors before attempting database work" do
      capture_log(fn ->
        assert {:error, "cannot read userbase file at missing-userbase.json"} =
                 FirehoseSimulator.create_userbase("missing-userbase.json")
      end)
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

  describe "import_userbase_from_csv/1" do
    test "returns manifest file errors before attempting database work" do
      capture_log(fn ->
        assert {:error, "cannot read userbase meta file at missing-userbase-meta.json"} =
                 FirehoseSimulator.import_userbase_from_csv("missing-userbase-meta.json")
      end)
    end
  end

  describe "vacuum/1" do
    test "returns action validation errors" do
      capture_log(fn ->
        assert {:error, "Select at least one vacuum action"} = FirehoseSimulator.vacuum([])
      end)
    end
  end

  describe "reset/0" do
    test "exposes global reset from the top-level api" do
      assert :ok = FirehoseSimulator.reset_all()
      assert :ok = FirehoseSimulator.reset()
    end
  end

  describe "shift_scenario/2" do
    test "shifts offsets for all plan sections" do
      scenario = %Scenario{
        posts: [%{offset_ms: 10, user_id: 1}],
        sessions: [%{offset_ms: 20, user_id: 2, duration_ms: 30_000}],
        follows: [%{offset_ms: 30, actor_id: 2, subject_id: 1}],
        request_interval_ms: 15_000,
        timeline_limit: 12
      }

      shifted = FirehoseSimulator.shift_scenario(scenario, 250)

      assert shifted.posts == [%{offset_ms: 260, user_id: 1}]
      assert shifted.sessions == [%{offset_ms: 270, user_id: 2, duration_ms: 30_000}]
      assert shifted.follows == [%{offset_ms: 280, actor_id: 2, subject_id: 1}]
      assert shifted.request_interval_ms == 15_000
      assert shifted.timeline_limit == 12
    end

    test "keeps nil sections unchanged" do
      scenario = %Scenario{posts: nil, sessions: nil, follows: nil}

      assert %Scenario{posts: nil, sessions: nil, follows: nil} =
               FirehoseSimulator.shift_scenario(scenario, 123)
    end
  end

  defp write_file!(tmp_dir, prefix, content) do
    path = Path.join(tmp_dir, "#{prefix}-#{System.unique_integer([:positive])}.json")
    File.write!(path, content)
    path
  end
end
