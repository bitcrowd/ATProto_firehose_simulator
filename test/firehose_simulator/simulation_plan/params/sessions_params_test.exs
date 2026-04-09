defmodule FirehoseSimulator.SimulationPlan.Params.SessionsParamsTest do
  use ExUnit.Case, async: false

  alias FirehoseSimulator.SimulationPlan.Params.SessionsParams

  describe "load/1" do
    test "returns a sessions struct for valid json" do
      assert {:ok, %SessionsParams{} = sessions} =
               SessionsParams.load("""
               {
                 "n": 1000000,
                 "max_active_user_id": 5000,
                 "follower_density": 2.0,
                 "seed": 42,
                 "time_units": 1,
                 "request_interval_ms": 45000,
                 "tiers": [
                   {"max_followers": 1000, "session_minutes": 240},
                   {"max_followers": 10000, "session_minutes": 480},
                   {"max_followers": 1000000, "session_minutes": 1000}
                 ]
               }
               """)

      assert sessions.n == 1_000_000
      assert sessions.max_active_user_id == 5_000
      assert sessions.follower_density == 2.0
      assert sessions.seed == 42
      assert sessions.time_units == 1
      assert sessions.request_interval_ms == 45_000
      assert Enum.map(sessions.tiers, & &1.session_minutes) == [240, 480, 1000]
    end

    test "defaults follower_density to 1.0 when omitted" do
      assert {:ok, %SessionsParams{} = sessions} =
               SessionsParams.load("""
               {
                 "n": 10,
                 "max_active_user_id": 5,
                 "seed": 1,
                 "time_units": 1,
                 "tiers": [
                   {"max_followers": 1000, "session_minutes": 240}
                 ]
               }
               """)

      assert sessions.follower_density == 1.0
      assert sessions.request_interval_ms == 30_000
    end

    test "returns an error for invalid request_interval_ms" do
      assert {:error, message} =
               SessionsParams.load("""
               {
                 "n": 10,
                 "max_active_user_id": 5,
                 "seed": 1,
                 "time_units": 1,
                 "request_interval_ms": 0,
                 "tiers": [
                   {"max_followers": 1000, "session_minutes": 240}
                 ]
               }
               """)

      assert String.contains?(message, "invalid sessions config:")
      assert String.contains?(message, "request_interval_ms")
    end

    test "returns an error for malformed json" do
      error_msg = "invalid sessions json"

      assert {:error, ^error_msg} = SessionsParams.load("{bad json")
    end

    test "returns embedded validation details for tiers" do
      assert {:error, message} =
               SessionsParams.load("""
               {
                 "n": 1000000,
                 "max_active_user_id": 5000,
                 "seed": 42,
                 "time_units": 1,
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
                 "n": 10,
                 "max_active_user_id": 5,
                 "seed": 1,
                 "time_units": 1,
                 "tiers": [
                   {"max_followers": 1000, "session_minutes": 240}
                 ]
               }
               """)
    end
  end

  describe "load_file/1" do
    @tag :tmp_dir
    test "reads sessions json from disk", %{tmp_dir: tmp_dir} do
      path =
        write_file!(
          tmp_dir,
          "sessions",
          """
          {
            "n": 10,
            "max_active_user_id": 5,
            "seed": 1,
            "time_units": 1,
            "tiers": [
              {"max_followers": 1000, "session_minutes": 240}
            ]
          }
          """
        )

      assert {:ok, %SessionsParams{}} = SessionsParams.load_file(path)
    end

    test "returns an error with file path when file does not exist" do
      path = "missing-sessions.json"
      error_msg = "cannot read sessions file at #{path}"

      assert {:error, ^error_msg} = SessionsParams.load_file(path)
    end
  end

  defp write_file!(tmp_dir, prefix, content) do
    path = Path.join(tmp_dir, "#{prefix}-#{System.unique_integer([:positive])}.json")
    File.write!(path, content)
    path
  end
end
