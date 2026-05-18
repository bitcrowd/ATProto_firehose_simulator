defmodule FirehoseSimulator.Scenario.JSONTest do
  use ExUnit.Case, async: true

  alias FirehoseSimulator.Scenario
  alias FirehoseSimulator.Scenario.JSON

  describe "encode/1" do
    test "encodes only persisted scenario fields" do
      scenario = %Scenario{
        posts: [%{offset_ms: 10, user_id: 1}],
        sessions: [%{offset_ms: 20, user_id: 2, duration_ms: 30_000}],
        follows: [%{offset_ms: 30, actor_id: 2, subject_id: 1}],
        request_interval_ms: 45_000,
        timeline_limit: 35,
        source_path: "/tmp/scenario.json"
      }

      assert {:ok, json} = JSON.encode(scenario)

      assert {:ok, scenario} = JSON.decode(json)

      assert scenario == %Scenario{
               posts: [%{offset_ms: 10, user_id: 1}],
               sessions: [%{offset_ms: 20, user_id: 2, duration_ms: 30_000}],
               follows: [%{offset_ms: 30, actor_id: 2, subject_id: 1}],
               request_interval_ms: 45_000,
               timeline_limit: 35
             }
    end
  end

  describe "decode/1" do
    test "decodes a full scenario json payload" do
      json = """
      {
        "posts": [{"offset_ms": 10, "user_id": 1}],
        "sessions": [{"offset_ms": 20, "user_id": 2, "duration_ms": 30000}],
        "follows": [{"offset_ms": 30, "actor_id": 2, "subject_id": 1}],
        "request_interval_ms": 45000,
        "timeline_limit": 35
      }
      """

      assert {:ok, scenario} = JSON.decode(json)

      assert scenario == %Scenario{
               posts: [%{offset_ms: 10, user_id: 1}],
               sessions: [%{offset_ms: 20, user_id: 2, duration_ms: 30_000}],
               follows: [%{offset_ms: 30, actor_id: 2, subject_id: 1}],
               request_interval_ms: 45_000,
               timeline_limit: 35
             }
    end

    test "allows missing or null event sections" do
      assert {:ok, scenario} =
               JSON.decode("""
               {
                 "posts": null,
                 "request_interval_ms": 15000,
                 "timeline_limit": 10
               }
               """)

      assert scenario.posts == nil
      assert scenario.sessions == nil
      assert scenario.follows == nil
      assert scenario.request_interval_ms == 15_000
      assert scenario.timeline_limit == 10
    end

    test "defaults omitted top-level timing fields" do
      assert {:ok, scenario} = JSON.decode("{}")

      assert scenario.request_interval_ms == 30_000
      assert scenario.timeline_limit == 20
    end

    test "rejects malformed json" do
      assert {:error, "invalid scenario json"} = JSON.decode("{")
    end

    test "rejects json values that are not objects" do
      assert {:error, "invalid scenario json: expected json object"} = JSON.decode("[]")
    end

    test "rejects event sections that are not lists or null" do
      assert {:error, "invalid posts: expected list or null"} =
               JSON.decode(~s({"posts": {"offset_ms": 10, "user_id": 1}}))
    end

    test "rejects event rows that are not objects" do
      assert {:error, "invalid sessions[0]: expected object"} =
               JSON.decode(~s({"sessions": [1]}))
    end

    test "rejects event rows with missing or non-integer fields" do
      assert {:error, "invalid follows[0]: subject_id must be an integer"} =
               JSON.decode(~s({"follows": [{"offset_ms": 1, "actor_id": 2}]}))

      assert {:error, "invalid posts[0]: offset_ms must be an integer"} =
               JSON.decode(~s({"posts": [{"offset_ms": "1", "user_id": 2}]}))
    end

    test "rejects non-positive top-level timing fields before building the scenario" do
      assert {:error, "invalid request_interval_ms: must be a positive integer"} =
               JSON.decode(~s({"request_interval_ms": 0}))

      assert {:error, "invalid timeline_limit: must be a positive integer"} =
               JSON.decode(~s({"timeline_limit": -1}))
    end
  end
end
