defmodule FirehoseSimulatorTest do
  use FirehoseSimulator.DataCase, async: false
  import ExUnit.CaptureLog
  alias FirehoseSimulator.BulkCreation.Actor
  alias FirehoseSimulator.BulkCreation.FeedItem
  alias FirehoseSimulator.BulkCreation.Follow
  alias FirehoseSimulator.BulkCreation.Post
  alias FirehoseSimulator.BulkCreation.Record
  alias FirehoseSimulator.Player
  alias FirehoseSimulator.Repo
  alias FirehoseSimulator.Scenario
  alias FirehoseSimulator.SimulationPlan
  alias FirehoseSimulator.SimulationPlan.Entry

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    original_run_storage_enabled = Application.get_env(:firehose_simulator, :run_storage_enabled)

    Application.put_env(:firehose_simulator, :run_storage_enabled, true)
    :ok = FirehoseSimulator.State.put_run_storage_directory(tmp_dir)
    clear_test_state()

    on_exit(fn ->
      Application.put_env(:firehose_simulator, :run_storage_enabled, original_run_storage_enabled)
      :ok = FirehoseSimulator.State.put_run_storage_directory(nil)
      clear_test_state()
    end)

    :ok
  end

  describe "generate_scenario_from_json_string/1" do
    test "loads scenario params" do
      assert {:ok, %Scenario{posts: posts}} =
               FirehoseSimulator.generate_scenario_from_json_string("""
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
               """)

      assert is_list(posts)
    end
  end

  describe "generate_scenario_from_json/1" do
    @tag :tmp_dir
    test "loads scenario params json from a path", %{tmp_dir: tmp_dir} do
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

      assert {:ok, %Scenario{} = scenario} =
               FirehoseSimulator.generate_scenario_from_json(params_path)

      assert is_list(scenario.posts)
      assert String.starts_with?(scenario.source_path, current_run_storage_directory())
      assert File.exists?(scenario.source_path)
    end

    test "returns file read errors for missing scenario params files" do
      assert {:error, "cannot read scenario params file at missing-scenario-params.json"} =
               FirehoseSimulator.generate_scenario_from_json("missing-scenario-params.json")
    end
  end

  describe "import_scenario_from_json_string/1" do
    test "imports full scenario json content" do
      assert {:ok, %Scenario{} = scenario} =
               FirehoseSimulator.import_scenario_from_json_string("""
               {
                 "posts": [{"offset_ms": 10, "user_id": 1}],
                 "sessions": [{"offset_ms": 20, "user_id": 2, "duration_ms": 30000}],
                 "follows": [{"offset_ms": 30, "actor_id": 2, "subject_id": 1}]
               }
               """)

      assert scenario.posts == [%{offset_ms: 10, user_id: 1}]
      assert scenario.sessions == [%{duration_ms: 30_000, offset_ms: 20, user_id: 2}]
      assert scenario.follows == [%{actor_id: 2, offset_ms: 30, subject_id: 1}]
    end
  end

  describe "import_scenario_from_json/1" do
    @tag :tmp_dir
    test "imports full scenario json from a path", %{tmp_dir: tmp_dir} do
      scenario_path =
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
               FirehoseSimulator.import_scenario_from_json(scenario_path)

      assert scenario.posts == [%{offset_ms: 10, user_id: 1}]
      assert scenario.sessions == [%{duration_ms: 30_000, offset_ms: 20, user_id: 2}]
      assert scenario.follows == [%{actor_id: 2, offset_ms: 30, subject_id: 1}]
    end

    test "returns file read errors for missing scenario json files" do
      assert {:error, "cannot read scenario json at missing-scenario.json"} =
               FirehoseSimulator.import_scenario_from_json("missing-scenario.json")
    end
  end

  describe "export_scenario_to_json/2" do
    @tag :tmp_dir
    test "exports full scenario json to a path", %{tmp_dir: tmp_dir} do
      scenario = %Scenario{
        posts: [%{offset_ms: 10, user_id: 1}],
        sessions: [%{offset_ms: 20, user_id: 2, duration_ms: 30_000}],
        follows: [%{offset_ms: 30, actor_id: 2, subject_id: 1}],
        request_interval_ms: 30_000,
        timeline_limit: 20
      }

      output_path = Path.join(tmp_dir, "exported-plan.json")

      assert :ok = FirehoseSimulator.export_scenario_to_json(scenario, output_path)
      assert File.exists?(output_path)

      assert {:ok, %Scenario{} = reloaded} =
               output_path
               |> File.read!()
               |> FirehoseSimulator.import_scenario_from_json_string()

      assert %{reloaded | source_path: nil} == scenario
    end
  end

  describe "current_simulation_plan" do
    test "returns the plan stored in state" do
      simulation_plan = %SimulationPlan{
        started_at: ~U[2025-01-01 00:00:00Z],
        entries: [
          %Entry{
            scenario_name: "stored-plan",
            scenario_path: "/tmp/stored-plan.json",
            offset_ms: 250
          }
        ]
      }

      assert :ok = FirehoseSimulator.State.put_simulation_plan(simulation_plan)
      assert FirehoseSimulator.current_simulation_plan() == simulation_plan
    end
  end

  describe "add_and_play_scenario" do
    @tag :tmp_dir
    test "adds the scenario to the stored plan and exports it", %{tmp_dir: tmp_dir} do
      scenario_path = Path.join(tmp_dir, "scenario.json")

      scenario = %Scenario{
        posts: [%{offset_ms: 10, user_id: 1}],
        sessions: nil,
        follows: nil,
        request_interval_ms: 30_000
      }

      assert {:ok, %SimulationPlan{} = simulation_plan} =
               FirehoseSimulator.add_and_play_scenario(
                 "added-scenario",
                 scenario,
                 250,
                 scenario_path
               )

      assert %Scenario{source_path: stored_scenario_path} =
               FirehoseSimulator.State.list_scenarios()["added-scenario"]

      assert File.exists?(stored_scenario_path)

      assert [%Entry{} = entry] = simulation_plan.entries
      assert entry.scenario_name == "added-scenario"
      assert entry.scenario_path == stored_scenario_path
      assert entry.offset_ms == 250
    end

    test "exports generated scenarios when scenario_path is blank" do
      scenario = %Scenario{
        posts: [%{offset_ms: 10, user_id: 1}],
        sessions: nil,
        follows: nil,
        request_interval_ms: 30_000
      }

      assert {:ok, %SimulationPlan{} = simulation_plan} =
               FirehoseSimulator.add_and_play_scenario(
                 "generated-scenario",
                 scenario,
                 0,
                 "   "
               )

      assert [%Entry{} = entry] = simulation_plan.entries

      assert Path.basename(entry.scenario_path) == "generated-scenario.json"
      assert File.exists?(entry.scenario_path)
    end
  end

  describe "import_simulation_plan_from_json" do
    @tag :tmp_dir
    test "loads plan entries, resolves relative paths, and stores the plan",
         %{tmp_dir: tmp_dir} do
      scenario_path =
        write_file!(
          tmp_dir,
          "import-scenario",
          """
          {
            "posts": [],
            "sessions": [],
            "follows": [],
            "request_interval_ms": 30000
          }
          """
        )

      plan_path =
        write_file!(
          tmp_dir,
          "simulation-plan",
          """
          {
            "name": "imported-plan",
            "entries": [
              {
                "scenario_name": "imported-entry",
                "scenario_path": "#{Path.basename(scenario_path)}",
                "offset_ms": 0
              }
            ]
          }
          """
        )

      assert {:ok, %SimulationPlan{} = simulation_plan} =
               FirehoseSimulator.import_simulation_plan_from_json(plan_path)

      assert simulation_plan.name == "imported-plan"

      assert [%Entry{} = entry] = simulation_plan.entries
      assert entry.scenario_name == "imported-entry"
      assert File.exists?(entry.scenario_path)
      assert %Scenario{source_path: source_path} = entry.scenario
      assert source_path == entry.scenario_path
      assert FirehoseSimulator.current_simulation_plan() == simulation_plan
      assert map_size(FirehoseSimulator.State.list_players()) == 1
    end

    @tag :tmp_dir
    test "applies elapsed plan time when a current plan has started",
         %{tmp_dir: tmp_dir} do
      scenario_path =
        write_file!(
          tmp_dir,
          "started-import-scenario",
          """
          {
            "posts": [],
            "sessions": [],
            "follows": [],
            "request_interval_ms": 30000
          }
          """
        )

      plan_path =
        write_file!(
          tmp_dir,
          "started-simulation-plan",
          """
          {
            "name": "started-imported-plan",
            "entries": [
              {
                "scenario_name": "started-imported-entry",
                "scenario_path": "#{Path.basename(scenario_path)}",
                "offset_ms": 250
              }
            ]
          }
          """
        )

      started_at = DateTime.add(DateTime.utc_now(), -2, :second)
      :ok = FirehoseSimulator.State.put_simulation_plan(%SimulationPlan{started_at: started_at})

      min_offset_ms = DateTime.diff(DateTime.utc_now(), started_at, :millisecond) + 250

      {:ok, simulation_plan} = FirehoseSimulator.import_simulation_plan_from_json(plan_path)

      max_offset_ms = DateTime.diff(DateTime.utc_now(), started_at, :millisecond) + 250

      assert [%Entry{} = entry] = simulation_plan.entries
      assert entry.offset_ms >= min_offset_ms
      assert entry.offset_ms <= max_offset_ms
    end

    @tag :tmp_dir
    test "bulk creates negative-offset entries instead of loading players",
         %{tmp_dir: tmp_dir} do
      post_user_id = unique_user_id()
      follow_actor_id = post_user_id + 1
      before_counts = row_counts([Actor, Post, Record, FeedItem, Follow])

      scenario_path =
        write_file!(
          tmp_dir,
          "preloaded-import-scenario",
          """
          {
            "posts": [{"offset_ms": 10, "user_id": #{post_user_id}}],
            "sessions": [],
            "follows": [{"offset_ms": 30, "actor_id": #{follow_actor_id}, "subject_id": #{post_user_id}}],
            "request_interval_ms": 30000
          }
          """
        )

      plan_path =
        write_file!(
          tmp_dir,
          "preloaded-simulation-plan",
          """
          {
            "name": "preloaded-imported-plan",
            "entries": [
              {
                "scenario_name": "preloaded-entry",
                "scenario_path": "#{Path.basename(scenario_path)}",
                "offset_ms": -100000
              }
            ]
          }
          """
        )

      {:ok, simulation_plan} = FirehoseSimulator.import_simulation_plan_from_json(plan_path)

      assert simulation_plan.name == "preloaded-imported-plan"
      assert [%Entry{} = entry] = simulation_plan.entries
      assert entry.scenario_name == "preloaded-entry"
      assert String.starts_with?(entry.scenario_path, current_run_storage_directory())
      assert entry.offset_ms == -100_000
      assert map_size(FirehoseSimulator.State.list_players()) == 0
      assert row_delta(before_counts, Actor) == 2
      assert row_delta(before_counts, Post) == 1
      assert row_delta(before_counts, Record) == 1
      assert row_delta(before_counts, FeedItem) == 1
      assert row_delta(before_counts, Follow) == 1
    end

    @tag :tmp_dir
    test "preloads negative entries and still loads non-negative entries",
         %{tmp_dir: tmp_dir} do
      preloaded_scenario_path =
        write_file!(
          tmp_dir,
          "mixed-preloaded-scenario",
          """
          {
            "posts": [{"offset_ms": 10, "user_id": 1}],
            "sessions": [],
            "follows": [],
            "request_interval_ms": 30000
          }
          """
        )

      loaded_scenario_path =
        write_file!(
          tmp_dir,
          "mixed-loaded-scenario",
          """
          {
            "posts": [],
            "sessions": [],
            "follows": [],
            "request_interval_ms": 30000
          }
          """
        )

      plan_path =
        write_file!(
          tmp_dir,
          "mixed-simulation-plan",
          """
          {
            "name": "mixed-imported-plan",
            "entries": [
              {
                "scenario_name": "preloaded-entry",
                "scenario_path": "#{Path.basename(preloaded_scenario_path)}",
                "offset_ms": -100000
              },
              {
                "scenario_name": "loaded-entry",
                "scenario_path": "#{Path.basename(loaded_scenario_path)}",
                "offset_ms": 0
              }
            ]
          }
          """
        )

      before_counts = row_counts([Actor, Post, Record, FeedItem, Follow])

      assert {:ok, %SimulationPlan{} = simulation_plan} =
               FirehoseSimulator.import_simulation_plan_from_json(plan_path)

      assert simulation_plan.name == "mixed-imported-plan"

      assert [%Entry{scenario_name: "preloaded-entry"}, %Entry{scenario_name: "loaded-entry"}] =
               simulation_plan.entries

      assert map_size(FirehoseSimulator.State.list_players()) == 1
      assert row_delta(before_counts, Actor) == 1
      assert row_delta(before_counts, Post) == 1
      assert row_delta(before_counts, Record) == 1
      assert row_delta(before_counts, FeedItem) == 1
      assert row_delta(before_counts, Follow) == 0
    end
  end

  describe "export_simulation_plan_to_json" do
    @tag :tmp_dir
    test "writes a plan", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "api-exported-plan.json")

      simulation_plan = %SimulationPlan{
        name: "api-exported",
        entries: [
          %Entry{
            scenario_name: "regular",
            scenario_path: "/tmp/scenario.json",
            offset_ms: 250
          }
        ]
      }

      assert :ok = FirehoseSimulator.export_simulation_plan_to_json(simulation_plan, path)
      assert File.exists?(path)
    end
  end

  describe "load/start/pause/stop" do
    setup do
      on_exit(fn ->
        _ = FirehoseSimulator.stop()
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

      assert {:ok, player_id, metadata} =
               FirehoseSimulator.load(scenario, scheduler_count: 1)

      assert is_binary(player_id)
      assert metadata.request_interval_ms == 15_000
      assert metadata.timeline_limit == 42
      assert metadata.lifecycle_state == :loaded

      [^player_id] = FirehoseSimulator.State.list_players() |> Map.keys()

      status = Player.status(player_id)
      refute status.running?
      assert status.loaded?

      assert :ok = FirehoseSimulator.start(player_id)
      assert Player.status(player_id).running?

      assert FirehoseSimulator.status(player_id).running?
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
    end

    test "stop/0 stops all players" do
      scenario = %Scenario{sessions: nil, posts: nil, follows: nil}

      assert {:ok, player_1, _meta_1} =
               FirehoseSimulator.load(scenario, scheduler_count: 1)

      assert {:ok, player_2, _meta_2} =
               FirehoseSimulator.load(scenario, scheduler_count: 1)

      assert :ok = FirehoseSimulator.start(player_1)
      assert :ok = FirehoseSimulator.start(player_2)
      assert map_size(FirehoseSimulator.State.list_players()) == 2

      assert :ok = FirehoseSimulator.stop()
      assert FirehoseSimulator.State.list_players() == %{}
    end
  end

  describe "load_with_offset/3" do
    setup do
      on_exit(fn ->
        _ = FirehoseSimulator.stop()
      end)

      :ok
    end

    test "shifts the plan before loading playback" do
      scenario = %Scenario{
        posts: [%{offset_ms: 10, user_id: 1}],
        sessions: nil,
        follows: nil
      }

      assert {:ok, player_id, metadata} =
               FirehoseSimulator.load_with_offset(scenario, 250, scheduler_count: 1)

      assert is_binary(player_id)
      assert metadata.lifecycle_state == :loaded

      [^player_id] = FirehoseSimulator.State.list_players() |> Map.keys()
      status = Player.status(player_id)
      assert status.loaded?
      refute status.running?
    end
  end

  describe "create_userbase/1" do
    test "loads userbase json through the top-level content api" do
      assert {:ok, result} =
               FirehoseSimulator.create_userbase_from_json("""
               {
                 "name": "created from json",
                 "num_users": 4,
                 "follower_density": 1.0
               }
               """)

      assert result.inserted_actor_count == 4
      assert result.inserted_follow_count == 4
    end

    test "returns file load errors before attempting database work" do
      assert {:error, "cannot read userbase file at missing-userbase.json"} =
               FirehoseSimulator.create_userbase("missing-userbase.json")
    end
  end

  describe "create_userbase/0" do
    @tag :tmp_dir
    test "loads the configured default userbase json path", %{tmp_dir: tmp_dir} do
      original_default_path =
        Application.fetch_env!(:firehose_simulator, :default_userbase_json_path)

      userbase_path =
        write_file!(
          tmp_dir,
          "default-userbase",
          """
          {
            "name": "created from default path",
            "num_users": 4,
            "follower_density": 1.0
          }
          """
        )

      Application.put_env(:firehose_simulator, :default_userbase_json_path, userbase_path)

      on_exit(fn ->
        Application.put_env(
          :firehose_simulator,
          :default_userbase_json_path,
          original_default_path
        )
      end)

      assert {:ok, result} = FirehoseSimulator.create_userbase()
      assert result.inserted_actor_count == 4
      assert result.inserted_follow_count == 4
    end
  end

  describe "export_userbase_to_csv" do
    @tag :tmp_dir
    test "exports under the current run directory by default", %{tmp_dir: tmp_dir} do
      userbase_path =
        write_file!(
          tmp_dir,
          "default-userbase",
          """
          {
            "name": "default csv export",
            "num_users": 4,
            "follower_density": 1.0
          }
          """
        )

      assert {:ok, result} = FirehoseSimulator.export_userbase_to_csv(userbase_path)

      assert File.exists?(result.meta_path)
      assert File.exists?(result.actor_csv_path)
      assert File.exists?(result.follow_csv_path)

      assert result.export_dir == Path.join(current_run_storage_directory(), "userbase")

      assert result.actor_csv_path ==
               Path.join(current_run_storage_directory(), "userbase/actor.csv")

      assert result.follow_csv_path ==
               Path.join(current_run_storage_directory(), "userbase/follow.csv")

      assert result.meta_path ==
               Path.join(current_run_storage_directory(), "userbase/userbase_meta.json")
    end

    @tag :tmp_dir
    test "exports a userbase file", %{tmp_dir: tmp_dir} do
      userbase_path =
        write_file!(
          tmp_dir,
          "file-userbase",
          """
          {
            "name": "csv file export",
            "num_users": 4,
            "follower_density": 1.0
          }
          """
        )

      export_dir = Path.join(tmp_dir, "file-export")

      assert {:ok, result} = FirehoseSimulator.export_userbase_to_csv(userbase_path, export_dir)

      assert result.export_dir == export_dir
      assert File.exists?(result.meta_path)
      assert File.exists?(result.actor_csv_path)
      assert File.exists?(result.follow_csv_path)
    end
  end

  describe "export_userbase_to_csv_from_json" do
    test "exports a userbase json through the top-level content api", %{tmp_dir: tmp_dir} do
      assert {:ok, result} =
               FirehoseSimulator.export_userbase_to_csv_from_json(
                 """
                 {
                   "name": "csv export",
                   "num_users": 4,
                   "follower_density": 1.0
                 }
                 """,
                 tmp_dir
               )

      assert File.exists?(result.meta_path)
      assert File.exists?(result.actor_csv_path)
      assert File.exists?(result.follow_csv_path)
    end
  end

  describe "import_userbase_from_csv/1" do
    test "imports manifest json" do
      meta_json = """
      {
        "version": 1,
        "kind": "userbase",
        "run_id": "test-run",
        "exported_at": "2025-01-01T00:00:00Z",
        "userbase": {
          "name": "imported userbase",
          "num_users": 2,
          "follower_density": 1.0
        },
        "files": {
          "actor": {
            "path": "/tmp/actors.csv",
            "row_count": 2
          },
          "follow": {
            "path": "/tmp/follows.csv",
            "row_count": 3
          }
        }
      }
      """

      copy_fun = fn _repo, meta ->
        assert meta.run_id == "test-run"
        {:ok, :copied}
      end

      assert {:ok, result} =
               FirehoseSimulator.import_userbase_from_csv_json(
                 meta_json,
                 validate_files: false,
                 copy_fun: copy_fun
               )

      assert result.inserted_actor_count == 2
      assert result.inserted_follow_count == 3
      assert is_binary(result.run_userbase_meta_path)
      assert File.exists?(result.run_userbase_meta_path)
    end

    @tag :tmp_dir
    test "imports a manifest file through the top-level path api", %{tmp_dir: tmp_dir} do
      export_dir = Path.join(tmp_dir, "userbase-export-for-import")

      assert {:ok, export_result} =
               FirehoseSimulator.export_userbase_to_csv_from_json(
                 """
                 {
                   "name": "exported then imported userbase",
                   "num_users": 2,
                   "follower_density": 1.0
                 }
                 """,
                 export_dir
               )

      meta_path =
        export_result.meta_path

      assert {:ok, result} = FirehoseSimulator.import_userbase_from_csv(meta_path)
      assert result.meta_path == meta_path
      assert result.inserted_actor_count == 2
      assert result.inserted_follow_count == 1
    end

    test "returns manifest file errors before attempting database work" do
      assert {:error, "cannot read userbase meta file at missing-userbase-meta.json"} =
               FirehoseSimulator.import_userbase_from_csv("missing-userbase-meta.json")
    end
  end

  describe "vacuum/1" do
    test "returns action validation errors" do
      capture_log(fn ->
        assert {:error, "Select at least one vacuum action"} = FirehoseSimulator.vacuum([])
      end)
    end
  end

  describe "bulk_create_scenario/1" do
    test "creates scenario data through the top-level api" do
      before_counts = row_counts([Actor, Post, Record, FeedItem, Follow])

      scenario = %Scenario{
        posts: [%{offset_ms: 10, user_id: unique_user_id()}],
        sessions: [],
        follows: []
      }

      assert {:ok, result} = FirehoseSimulator.bulk_create_scenario(scenario)
      assert result.inserted_post_count == 1

      assert row_delta(before_counts, Actor) == 1
      assert row_delta(before_counts, Post) == 1
      assert row_delta(before_counts, Record) == 1
      assert row_delta(before_counts, FeedItem) == 1
      assert row_delta(before_counts, Follow) == 0
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

  defp clear_test_state do
    {:ok, simulation_plan} = SimulationPlan.new(%{entries: []})
    :ok = FirehoseSimulator.stop()
    :ok = FirehoseSimulator.State.clear_scenarios()
    :ok = FirehoseSimulator.State.clear_players()
    :ok = FirehoseSimulator.State.put_simulation_plan(simulation_plan)
    :ok = FirehoseSimulator.State.put_userbase_result(false, nil)
    :ok
  end

  defp row_count(schema) do
    Repo.aggregate(schema, :count)
  end

  defp row_counts(schemas) do
    Map.new(schemas, fn schema -> {schema, row_count(schema)} end)
  end

  defp row_delta(before_counts, schema) do
    row_count(schema) - Map.fetch!(before_counts, schema)
  end

  defp unique_user_id do
    System.unique_integer([:positive]) + 2_000_000
  end

  defp current_run_storage_directory do
    FirehoseSimulator.State.get_run_storage_directory()
  end
end
