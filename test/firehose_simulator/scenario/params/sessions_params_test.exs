defmodule FirehoseSimulator.Scenario.Params.SessionsParamsTest do
  use ExUnit.Case, async: false

  alias FirehoseSimulator.Scenario.Params.SessionsParams

  describe "load/1" do
    test "returns a sessions struct for valid json" do
      assert {:ok, %SessionsParams{} = sessions} =
               SessionsParams.load("""
               {
                 "num_users": 1000000,
                 "max_active_user_id": 5000,
                 "follower_density": 2.0,
                 "request_interval_ms": 45000,
                 "timeline_limit": 50,
                 "tiers": [
                   {"max_followers": 1000, "session_minutes": 240},
                   {"max_followers": 10000, "session_minutes": 480},
                   {"max_followers": 1000000, "session_minutes": 1000}
                 ]
               }
               """)

      assert sessions.num_users == 1_000_000
      assert sessions.max_active_user_id == 5_000
      assert sessions.follower_density == 2.0
      assert sessions.request_interval_ms == 45_000
      assert sessions.timeline_limit == 50
      assert Enum.map(sessions.tiers, & &1.session_minutes) == [240, 480, 1000]
    end

    test "defaults follower_density, request_interval_ms and timeline_limit when omitted" do
      assert {:ok, %SessionsParams{} = sessions} =
               SessionsParams.load("""
               {
                 "num_users": 10,
                 "max_active_user_id": 5,
                 "tiers": [
                   {"max_followers": 1000, "session_minutes": 240}
                 ]
               }
               """)

      assert sessions.follower_density == 1.0
      assert sessions.request_interval_ms == 30_000
      assert sessions.timeline_limit == 20
    end

    test "returns an error for invalid request_interval_ms" do
      assert {:error, message} =
               SessionsParams.load("""
               {
                 "num_users": 10,
                 "max_active_user_id": 5,
                 "request_interval_ms": 0,
                 "tiers": [
                   {"max_followers": 1000, "session_minutes": 240}
                 ]
               }
               """)

      assert String.contains?(message, "invalid sessions config:")
      assert String.contains?(message, "request_interval_ms")
    end

    test "returns an error for invalid timeline_limit" do
      assert {:error, message} =
               SessionsParams.load("""
               {
                 "timeline_limit": 0,
                 "tiers": [
                   {"max_followers": 1000, "session_minutes": 240}
                 ]
               }
               """)

      assert String.contains?(message, "invalid sessions config:")
      assert String.contains?(message, "timeline_limit")
    end

    test "returns an error for malformed json" do
      error_msg = "invalid sessions json"

      assert {:error, ^error_msg} = SessionsParams.load("{bad json")
    end

    test "returns embedded validation details for tiers" do
      assert {:error, message} =
               SessionsParams.load("""
               {
                 "num_users": 1000000,
                 "max_active_user_id": 5000,
                 "tiers": [
                   {"max_followers": 1000}
                 ]
               }
               """)

      assert String.contains?(message, "invalid sessions config:")
      assert String.contains?(message, "tiers")
    end
  end

  describe "load!/1" do
    test "returns the sessions config on success" do
      assert %SessionsParams{} =
               SessionsParams.load!("""
               {
                 "num_users": 10,
                 "max_active_user_id": 5,
                 "tiers": [
                   {"max_followers": 1000, "session_minutes": 240}
                 ]
               }
               """)
    end
  end

  describe "load_file/1" do
    test "returns an error with file path when file does not exist" do
      path = "missing-sessions.json"
      error_msg = "cannot read sessions file at #{path}"

      assert {:error, ^error_msg} = SessionsParams.load_file(path)
    end
  end
end
