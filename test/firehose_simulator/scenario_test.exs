defmodule FirehoseSimulator.ScenarioTest do
  use ExUnit.Case, async: false

  alias FirehoseSimulator.Scenario

  describe "generate_from_json_string/1" do
    test "loads unified params json and generates posts, sessions, and follows plans" do
      params_json = """
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

      assert {:ok,
              %Scenario{
                posts: posts,
                sessions: sessions,
                follows: follows,
                request_interval_ms: request_interval_ms,
                timeline_limit: timeline_limit
              }} =
               Scenario.generate_from_json_string(params_json)

      assert length(sessions) == 5
      assert is_list(posts)
      assert is_list(follows)
      assert request_interval_ms == 25_000
      assert timeline_limit == 40
      assert Enum.all?(sessions, &(&1.offset_ms < 3_600_000))
      assert Enum.all?(posts, &(&1.offset_ms < 3_600_000))
      assert Enum.all?(follows, &(&1.offset_ms < 3_600_000))
    end

    test "defaults time unit duration to one day when omitted" do
      params_json = """
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

      assert {:ok,
              %Scenario{
                posts: posts,
                sessions: sessions,
                follows: follows,
                request_interval_ms: request_interval_ms,
                timeline_limit: timeline_limit
              }} =
               Scenario.generate_from_json_string(params_json)

      assert request_interval_ms == 30_000
      assert timeline_limit == 20
      assert Enum.all?(sessions, &(&1.offset_ms < 86_400_000))
      assert Enum.all?(posts, &(&1.offset_ms < 86_400_000))
      assert Enum.all?(follows, &(&1.offset_ms < 86_400_000))
    end
  end

  describe "generate_from_json/1" do
    test "requires a scenario_params path" do
      assert {:error, "scenario_params path is required"} =
               Scenario.generate_from_json([])
    end
  end

  describe "to_json/1 and from_json/1" do
    test "round-trips a full scenario struct" do
      scenario = %Scenario{
        posts: [%{offset_ms: 10, user_id: 1}],
        sessions: [%{offset_ms: 20, user_id: 2, duration_ms: 30_000}],
        follows: [%{offset_ms: 30, actor_id: 2, subject_id: 1}],
        request_interval_ms: 45_000,
        timeline_limit: 35
      }

      assert {:ok, json} = Scenario.to_json(scenario)
      assert {:ok, decoded} = Scenario.from_json(json)
      assert decoded == scenario
    end

    test "defaults request_interval_ms and timeline_limit when decoding legacy json without them" do
      legacy_json = """
      {
        "posts": [{"offset_ms": 10, "user_id": 1}],
        "sessions": [{"offset_ms": 20, "user_id": 2, "duration_ms": 30000}],
        "follows": [{"offset_ms": 30, "actor_id": 2, "subject_id": 1}]
      }
      """

      assert {:ok, decoded} = Scenario.from_json(legacy_json)
      assert decoded.request_interval_ms == 30_000
      assert decoded.timeline_limit == 20
    end
  end

  describe "shift/2" do
    test "shifts offsets for all plan sections" do
      scenario = %Scenario{
        posts: [%{offset_ms: 10, user_id: 1}],
        sessions: [%{offset_ms: 20, user_id: 2, duration_ms: 30_000}],
        follows: [%{offset_ms: 30, actor_id: 2, subject_id: 1}],
        request_interval_ms: 15_000,
        timeline_limit: 12
      }

      shifted = Scenario.shift(scenario, 250)

      assert shifted.posts == [%{offset_ms: 260, user_id: 1}]
      assert shifted.sessions == [%{offset_ms: 270, user_id: 2, duration_ms: 30_000}]
      assert shifted.follows == [%{offset_ms: 280, actor_id: 2, subject_id: 1}]
      assert shifted.request_interval_ms == 15_000
      assert shifted.timeline_limit == 12
    end

    test "keeps nil sections unchanged" do
      scenario = %Scenario{posts: nil, sessions: nil, follows: nil}

      assert %Scenario{posts: nil, sessions: nil, follows: nil} =
               Scenario.shift(scenario, 123)
    end
  end
end
