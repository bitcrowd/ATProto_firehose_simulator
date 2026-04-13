defmodule FirehoseSimulator.SimulationPlanTest do
  use ExUnit.Case, async: false

  alias FirehoseSimulator.SimulationPlan

  describe "generate_from_json/1" do
    @tag :tmp_dir
    test "loads unified params json and generates posts, sessions, and follows plans",
         %{tmp_dir: tmp_dir} do
      params_path =
        write_file!(
          tmp_dir,
          "simulation-plan-params",
          """
          {
            "seed": 1,
            "time_units": 1,
            "time_unit_duration_ms": 3600000,
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
        )

      assert {:ok,
              %SimulationPlan{
                posts: posts,
                sessions: sessions,
                follows: follows,
                request_interval_ms: request_interval_ms
              }} =
               SimulationPlan.generate_from_json(simulation_plan_params: params_path)

      assert length(sessions) == 5
      assert is_list(posts)
      assert is_list(follows)
      assert request_interval_ms == 25_000
      assert Enum.all?(sessions, &(&1.offset_ms < 3_600_000))
      assert Enum.all?(posts, &(&1.offset_ms < 3_600_000))
      assert Enum.all?(follows, &(&1.offset_ms < 3_600_000))
    end

    test "returns nil for sections without a path" do
      assert {:ok,
              %SimulationPlan{
                posts: nil,
                sessions: nil,
                follows: nil,
                request_interval_ms: 30_000
              }} =
               SimulationPlan.generate_from_json([])
    end

    @tag :tmp_dir
    test "defaults time unit duration to one day when omitted", %{tmp_dir: tmp_dir} do
      params_path =
        write_file!(
          tmp_dir,
          "simulation-plan-params-default-duration",
          """
          {
            "seed": 1,
            "time_units": 1,
            "posts_params": {
              "num_users": 10,
              "max_active_user_id": 1,
              "tiers": [
                {"max_followers": 1000, "posts_per_time_unit": 1.0}
              ]
            },
            "sessions_params": {
              "num_users": 10,
              "max_active_user_id": 1,
              "tiers": [
                {"max_followers": 1000, "session_minutes": 10}
              ]
            },
            "follows_params": {
              "num_users": 10,
              "max_active_user_id": 1,
              "tiers": [
                {"max_followers": 1000, "follows_per_time_unit": 1.0}
              ]
            }
          }
          """
        )

      assert {:ok,
              %SimulationPlan{
                posts: posts,
                sessions: sessions,
                follows: follows,
                request_interval_ms: request_interval_ms
              }} =
               SimulationPlan.generate_from_json(simulation_plan_params: params_path)

      assert request_interval_ms == 30_000
      assert Enum.all?(sessions, &(&1.offset_ms < 86_400_000))
      assert Enum.all?(posts, &(&1.offset_ms < 86_400_000))
      assert Enum.all?(follows, &(&1.offset_ms < 86_400_000))
    end
  end

  describe "to_json/1 and from_json/1" do
    test "round-trips a full simulation plan struct" do
      simulation_plan = %SimulationPlan{
        posts: [%{offset_ms: 10, user_id: 1}],
        sessions: [%{offset_ms: 20, user_id: 2, duration_ms: 30_000}],
        follows: [%{offset_ms: 30, actor_id: 2, subject_id: 1}],
        request_interval_ms: 45_000
      }

      assert {:ok, json} = SimulationPlan.to_json(simulation_plan)
      assert {:ok, decoded} = SimulationPlan.from_json(json)
      assert decoded == simulation_plan
    end

    test "defaults request_interval_ms when decoding legacy json without it" do
      legacy_json = """
      {
        "posts": [{"offset_ms": 10, "user_id": 1}],
        "sessions": [{"offset_ms": 20, "user_id": 2, "duration_ms": 30000}],
        "follows": [{"offset_ms": 30, "actor_id": 2, "subject_id": 1}]
      }
      """

      assert {:ok, decoded} = SimulationPlan.from_json(legacy_json)
      assert decoded.request_interval_ms == 30_000
    end
  end

  describe "shift/2" do
    test "shifts offsets for all plan sections" do
      simulation_plan = %SimulationPlan{
        posts: [%{offset_ms: 10, user_id: 1}],
        sessions: [%{offset_ms: 20, user_id: 2, duration_ms: 30_000}],
        follows: [%{offset_ms: 30, actor_id: 2, subject_id: 1}],
        request_interval_ms: 15_000
      }

      shifted = SimulationPlan.shift(simulation_plan, 250)

      assert shifted.posts == [%{offset_ms: 260, user_id: 1}]
      assert shifted.sessions == [%{offset_ms: 270, user_id: 2, duration_ms: 30_000}]
      assert shifted.follows == [%{offset_ms: 280, actor_id: 2, subject_id: 1}]
      assert shifted.request_interval_ms == 15_000
    end

    test "keeps nil sections unchanged" do
      simulation_plan = %SimulationPlan{posts: nil, sessions: nil, follows: nil}

      assert %SimulationPlan{posts: nil, sessions: nil, follows: nil} =
               SimulationPlan.shift(simulation_plan, 123)
    end
  end

  defp write_file!(tmp_dir, prefix, content) do
    path = Path.join(tmp_dir, "#{prefix}-#{System.unique_integer([:positive])}.json")
    File.write!(path, content)
    path
  end
end
