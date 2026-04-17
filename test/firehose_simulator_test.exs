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
  alias FirehoseSimulator.SimulationPlan.JSON

  setup do
    runs_root =
      Path.join(
        System.tmp_dir!(),
        "firehose-simulator-runs-#{System.unique_integer([:positive, :monotonic])}"
      )

    Application.put_env(:firehose_simulator, :runs_root, runs_root)
    clear_test_state()

    on_exit(fn ->
      Application.delete_env(:firehose_simulator, :runs_root)
      clear_test_state()
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

      assert %{reloaded | source_path: nil} == %{scenario | source_path: nil}
      assert String.contains?(reloaded.source_path, "firehose-simulator-runs-")
      assert File.exists?(reloaded.source_path)
    end
  end

  describe "simulation plans" do
    test "encodes simulation plan json with name and entries" do
      started_at = ~U[2025-01-01 00:00:00Z]

      simulation_plan = %SimulationPlan{
        name: "nightly-load",
        started_at: started_at,
        export_path: "/tmp/simulation-plan.json",
        entries: [
          %Entry{
            scenario_name: "regular",
            scenario_path: "/tmp/scenario.json",
            offset_ms: 250
          }
        ]
      }

      assert {:ok, json} = JSON.encode(simulation_plan)
      assert {:ok, decoded} = Jason.decode(json)

      assert decoded["name"] == "nightly-load"
      refute Map.has_key?(decoded, "started_at")
      refute Map.has_key?(decoded, "export_path")

      assert decoded["entries"] == [
               %{
                 "scenario_name" => "regular",
                 "scenario_path" => "/tmp/scenario.json",
                 "offset_ms" => 250
               }
             ]
    end

    test "decodes simulation plan json into a simulation plan struct" do
      assert {:ok, %SimulationPlan{} = simulation_plan} =
               JSON.decode("""
               {
                 "name": "nightly-load",
                 "entries": [
                   {
                     "scenario_name": "regular",
                     "scenario_path": "/tmp/scenario.json",
                     "offset_ms": 250
                   }
                 ]
               }
               """)

      assert simulation_plan.name == "nightly-load"
      assert simulation_plan.started_at == nil
      assert simulation_plan.export_path == nil
      assert [%Entry{} = entry] = simulation_plan.entries
      assert entry.scenario_name == "regular"
      assert entry.scenario_path == "/tmp/scenario.json"
      assert entry.offset_ms == 250
      assert entry.scenario == nil
    end

    @tag :tmp_dir
    test "exports a simulation plan snapshot to a provided path", %{
      tmp_dir: tmp_dir
    } do
      path = Path.join(tmp_dir, "simulation-plan.json")

      simulation_plan = %SimulationPlan{
        name: "generated-plan",
        entries: [
          %Entry{
            scenario_name: "regular",
            scenario_path: "/tmp/scenario.json",
            offset_ms: 250
          }
        ]
      }

      assert {:ok, ^path} = JSON.export_to_file(simulation_plan, path)
      assert File.exists?(path)

      assert {:ok, decoded} = File.read(path)
      assert {:ok, %SimulationPlan{} = reloaded} = JSON.decode(decoded)
      assert reloaded.name == "generated-plan"
      assert [%Entry{scenario_name: "regular", offset_ms: 250}] = reloaded.entries
    end

    test "entry changeset accepts an embedded scenario struct" do
      scenario = %Scenario{
        posts: [%{offset_ms: 10, user_id: 1}],
        sessions: nil,
        follows: nil,
        request_interval_ms: 30_000
      }

      assert {:ok, %Entry{} = entry} =
               Entry.new(%{
                 "scenario_name" => "embedded-plan",
                 "scenario_path" => "/tmp/embedded-plan.json",
                 "offset_ms" => 100,
                 "scenario" => scenario
               })

      assert entry.scenario == scenario
    end

    test "current_simulation_plan/0 returns the plan stored in state" do
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

    @tag :tmp_dir
    test "add_and_play_scenario/4 adds the scenario to the stored plan and exports it", %{
      tmp_dir: tmp_dir
    } do
      scenario_path = Path.join(tmp_dir, "scenario.json")
      File.write!(scenario_path, ~s({"posts":[],"sessions":[],"follows":[]}))

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

      assert simulation_plan.export_path
      assert File.exists?(simulation_plan.export_path)
      assert String.contains?(simulation_plan.export_path, "firehose-simulator-runs-")
      assert FirehoseSimulator.current_simulation_plan() == simulation_plan

      assert %Scenario{source_path: stored_scenario_path} =
               FirehoseSimulator.State.list_scenarios()["added-scenario"]

      assert String.contains?(stored_scenario_path, "firehose-simulator-runs-")
      assert File.exists?(stored_scenario_path)

      assert [%Entry{} = entry] = simulation_plan.entries
      assert entry.scenario_name == "added-scenario"
      assert entry.scenario_path == stored_scenario_path
      assert entry.offset_ms == 250
    end

    @tag :tmp_dir
    test "add_and_play_scenario/4 exports generated scenarios when scenario_path is blank",
         _context do
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
      assert entry.scenario_name == "generated-scenario"
      assert entry.offset_ms == 0
      assert is_binary(entry.scenario_path)
      assert entry.scenario_path != ""
      assert String.contains?(entry.scenario_path, "firehose-simulator-runs-")
      assert File.exists?(entry.scenario_path)

      assert %Scenario{source_path: source_path} =
               FirehoseSimulator.State.list_scenarios()["generated-scenario"]

      assert source_path == entry.scenario_path

      assert {:ok, %Scenario{} = reloaded} =
               FirehoseSimulator.import_scenario_from_json(entry.scenario_path)

      assert %{reloaded | source_path: nil} == scenario
    end

    @tag :tmp_dir
    test "import_simulation_plan_from_json/1 loads plan entries, resolves relative paths, and stores the plan",
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

      capture_log(fn ->
        send(self(), {:result, FirehoseSimulator.import_simulation_plan_from_json(plan_path)})
      end)

      assert_receive {:result, {:ok, %SimulationPlan{} = simulation_plan}}

      assert simulation_plan.name == "imported-plan"

      assert [%Entry{} = entry] = simulation_plan.entries
      assert entry.scenario_name == "imported-entry"
      assert String.contains?(entry.scenario_path, "firehose-simulator-runs-")
      assert File.exists?(entry.scenario_path)
      assert %Scenario{source_path: source_path} = entry.scenario
      assert source_path == entry.scenario_path
      assert FirehoseSimulator.current_simulation_plan() == simulation_plan
      assert map_size(FirehoseSimulator.State.list_players()) == 1
    end

    @tag :tmp_dir
    test "import_simulation_plan_from_json/1 applies elapsed plan time when a current plan has started",
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

      assert simulation_plan.name == "started-imported-plan"
      assert [%Entry{} = entry] = simulation_plan.entries
      assert entry.scenario_name == "started-imported-entry"
      assert String.contains?(entry.scenario_path, "firehose-simulator-runs-")
      assert File.exists?(entry.scenario_path)
      assert entry.offset_ms >= min_offset_ms
      assert entry.offset_ms <= max_offset_ms
      assert %Scenario{source_path: source_path} = entry.scenario
      assert source_path == entry.scenario_path
      assert FirehoseSimulator.current_simulation_plan() == simulation_plan
      assert map_size(FirehoseSimulator.State.list_players()) == 1
    end

    @tag :tmp_dir
    test "import_simulation_plan_from_json/1 bulk creates negative-offset entries instead of loading players",
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
      assert String.contains?(entry.scenario_path, "firehose-simulator-runs-")
      assert entry.offset_ms == -100_000
      assert map_size(FirehoseSimulator.State.list_players()) == 0
      assert row_delta(before_counts, Actor) == 2
      assert row_delta(before_counts, Post) == 1
      assert row_delta(before_counts, Record) == 1
      assert row_delta(before_counts, FeedItem) == 1
      assert row_delta(before_counts, Follow) == 1
    end

    @tag :tmp_dir
    test "import_simulation_plan_from_json/1 preloads negative entries and still loads non-negative entries",
         %{tmp_dir: tmp_dir} do
      post_user_id = unique_user_id()
      before_counts = row_counts([Actor, Post, Record, FeedItem, Follow])

      preloaded_scenario_path =
        write_file!(
          tmp_dir,
          "mixed-preloaded-scenario",
          """
          {
            "posts": [{"offset_ms": 10, "user_id": #{post_user_id}}],
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

      capture_log(fn ->
        send(self(), {:result, FirehoseSimulator.import_simulation_plan_from_json(plan_path)})
      end)

      assert_receive {:result, {:ok, %SimulationPlan{} = simulation_plan}}

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

    @tag :tmp_dir
    test "import_simulation_plan_from_json/1 keeps combined offsets for negative entries in a running plan",
         %{tmp_dir: tmp_dir} do
      post_user_id = unique_user_id()
      before_counts = row_counts([Actor, Post, Record, FeedItem])

      scenario_path =
        write_file!(
          tmp_dir,
          "started-preloaded-import-scenario",
          """
          {
            "posts": [{"offset_ms": 10, "user_id": #{post_user_id}}],
            "sessions": [],
            "follows": [],
            "request_interval_ms": 30000
          }
          """
        )

      plan_path =
        write_file!(
          tmp_dir,
          "started-preloaded-simulation-plan",
          """
          {
            "name": "started-preloaded-plan",
            "entries": [
              {
                "scenario_name": "started-preloaded-entry",
                "scenario_path": "#{Path.basename(scenario_path)}",
                "offset_ms": -250
              }
            ]
          }
          """
        )

      assert map_size(FirehoseSimulator.State.list_players()) == 0

      started_at = DateTime.add(DateTime.utc_now(), -2, :second)
      :ok = FirehoseSimulator.State.put_simulation_plan(%SimulationPlan{started_at: started_at})

      min_offset_ms = DateTime.diff(DateTime.utc_now(), started_at, :millisecond) - 250

      {:ok, simulation_plan} = FirehoseSimulator.import_simulation_plan_from_json(plan_path)

      max_offset_ms = DateTime.diff(DateTime.utc_now(), started_at, :millisecond) - 250

      assert simulation_plan.name == "started-preloaded-plan"
      assert [%Entry{} = entry] = simulation_plan.entries
      assert entry.scenario_name == "started-preloaded-entry"
      assert entry.offset_ms >= min_offset_ms
      assert entry.offset_ms <= max_offset_ms
      assert map_size(FirehoseSimulator.State.list_players()) == 0
      assert row_delta(before_counts, Actor) == 1
      assert row_delta(before_counts, Post) == 1
      assert row_delta(before_counts, Record) == 1
      assert row_delta(before_counts, FeedItem) == 1
    end

    @tag :tmp_dir
    test "export_simulation_plan_to_json/2 writes a plan through the top-level api", %{
      tmp_dir: tmp_dir
    } do
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
      assert {:ok, json} = File.read(path)
      assert {:ok, %SimulationPlan{name: "api-exported"}} = JSON.decode(json)
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
    :ok = FirehoseSimulator.stop_all()
    :ok = FirehoseSimulator.State.clear_scenarios()
    :ok = FirehoseSimulator.State.clear_players()
    _run_dir = FirehoseSimulator.State.refresh_run_storage_directory()
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
end
