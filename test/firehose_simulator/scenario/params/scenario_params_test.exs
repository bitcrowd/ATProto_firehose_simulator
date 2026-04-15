defmodule FirehoseSimulator.Scenario.Params.ScenarioParamsTest do
  use ExUnit.Case, async: false

  alias FirehoseSimulator.Scenario.Params.ScenarioParams

  describe "load/1" do
    test "returns a struct for valid unified json" do
      assert {:ok, %ScenarioParams{} = params} =
               ScenarioParams.load("""
               {
                 "seed": 1,
                 "time_units": 1,
                 "time_unit_duration_ms": 3600000,
                 "posts_params": {
                   "num_users": 10,
                   "max_active_user_id": 5,
                   "tiers": [
                     {"max_followers": 1000, "posts_per_time_unit": 0.25}
                   ]
                 },
                 "sessions_params": {
                   "num_users": 10,
                   "max_active_user_id": 5,
                   "request_interval_ms": 15000,
                   "tiers": [
                     {"max_followers": 1000, "session_minutes": 240}
                   ]
                 },
                 "follows_params": {
                   "num_users": 10,
                   "max_active_user_id": 5,
                   "tiers": [
                     {"max_followers": 1000, "follows_per_time_unit": 0.25}
                   ]
                 }
               }
               """)

      assert params.seed == 1
      assert params.time_units == 1
      assert params.time_unit_duration_ms == 3_600_000
      assert params.posts_params.num_users == 10
      assert params.sessions_params.num_users == 10
      assert params.sessions_params.request_interval_ms == 15_000
      assert params.follows_params.num_users == 10
    end

    test "validates required top-level fields" do
      assert {:error, message} =
               ScenarioParams.load("""
               {
                 "time_unit_duration_ms": 3600000
               }
               """)

      assert String.contains?(message, "invalid scenario params config:")
      assert String.contains?(message, "seed")
      assert String.contains?(message, "time_units")
    end

    test "validates time_unit_duration_ms when provided" do
      assert {:error, message} =
               ScenarioParams.load("""
               {
                 "seed": 1,
                 "time_units": 1,
                 "time_unit_duration_ms": 0
               }
               """)

      assert String.contains?(message, "invalid scenario params config:")
      assert String.contains?(message, "time_unit_duration_ms")
    end

    test "supports optional sections" do
      assert {:ok, %ScenarioParams{} = params} =
               ScenarioParams.load("""
               {
                 "seed": 1,
                 "time_units": 1
               }
               """)

      assert params.seed == 1
      assert params.time_units == 1
      assert is_nil(params.time_unit_duration_ms)
      assert is_nil(params.posts_params)
      assert is_nil(params.sessions_params)
      assert is_nil(params.follows_params)
    end
  end

  describe "load_file/1" do
    @tag :tmp_dir
    test "reads unified json from disk", %{tmp_dir: tmp_dir} do
      path = write_file!(tmp_dir, "scenario-params", ~s({"seed":1,"time_units":1}))
      assert {:ok, %ScenarioParams{}} = ScenarioParams.load_file(path)
    end

    test "returns an error with file path when file does not exist" do
      path = "missing-scenario-params.json"
      error_msg = "cannot read scenario params file at #{path}"

      assert {:error, ^error_msg} = ScenarioParams.load_file(path)
    end
  end

  defp write_file!(tmp_dir, prefix, content) do
    path = Path.join(tmp_dir, "#{prefix}-#{System.unique_integer([:positive])}.json")
    File.write!(path, content)
    path
  end
end
