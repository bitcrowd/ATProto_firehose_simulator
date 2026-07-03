defmodule FirehoseSimulator.ScenarioTest do
  use ExUnit.Case, async: false

  alias FirehoseSimulator.Scenario

  describe "new/1" do
    test "builds a validated scenario" do
      assert {:ok, %Scenario{} = scenario} =
               Scenario.new(%{
                 posts: [%{offset_ms: 10, user_id: 1}],
                 sessions: [%{offset_ms: 20, user_id: 2, duration_ms: 30_000}],
                 follows: [%{offset_ms: 30, actor_id: 2, subject_id: 1}],
                 request_interval_ms: 45_000,
                 timeline_limit: 35
               })

      assert scenario.request_interval_ms == 45_000
      assert scenario.timeline_limit == 35
    end

    test "rejects non-positive top-level numeric fields" do
      assert {:error, changeset} =
               Scenario.new(%{
                 request_interval_ms: 0,
                 timeline_limit: -1
               })

      assert "must be greater than 0" in errors_on(changeset).request_interval_ms
      assert "must be greater than 0" in errors_on(changeset).timeline_limit
    end

    test "rejects blank source paths from string-key attrs" do
      assert {:error, changeset} = Scenario.new(%{"source_path" => "   "})

      assert "should be at least 1 character(s)" in errors_on(changeset).source_path
    end
  end

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

      assert [_, _, _, _, _] = sessions
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

  describe "put_source_path/2" do
    test "trims valid source paths" do
      scenario = %Scenario{}

      assert {:ok, %Scenario{source_path: "/tmp/scenario.json"}} =
               Scenario.put_source_path(scenario, "  /tmp/scenario.json  ")
    end

    test "rejects blank source paths" do
      assert {:error, changeset} = Scenario.put_source_path(%Scenario{}, "   ")

      assert "should be at least 1 character(s)" in errors_on(changeset).source_path
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
        timeline_limit: 12,
        source_path: "/tmp/scenario.json"
      }

      shifted = Scenario.shift(scenario, 250)

      assert shifted.posts == [%{offset_ms: 260, user_id: 1}]
      assert shifted.sessions == [%{offset_ms: 270, user_id: 2, duration_ms: 30_000}]
      assert shifted.follows == [%{offset_ms: 280, actor_id: 2, subject_id: 1}]
      assert shifted.request_interval_ms == 15_000
      assert shifted.timeline_limit == 12
      assert shifted.source_path == "/tmp/scenario.json"
    end

    test "keeps nil sections unchanged" do
      scenario = %Scenario{posts: nil, sessions: nil, follows: nil}

      assert %Scenario{posts: nil, sessions: nil, follows: nil} =
               Scenario.shift(scenario, 123)
    end
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
