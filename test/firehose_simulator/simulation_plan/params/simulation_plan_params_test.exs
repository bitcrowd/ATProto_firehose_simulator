defmodule FirehoseSimulator.SimulationPlan.Params.SimulationPlanParamsTest do
  use ExUnit.Case, async: false

  alias FirehoseSimulator.SimulationPlan.Params.SimulationPlanParams

  describe "load/1" do
    test "returns a struct for valid unified json" do
      assert {:ok, %SimulationPlanParams{} = params} =
               SimulationPlanParams.load("""
               {
                 "posts_params": {
                   "n": 10,
                   "max_active_user_id": 5,
                   "seed": 1,
                   "time_units": 1,
                   "tiers": [
                     {"max_followers": 1000, "posts_per_time_unit": 0.25}
                   ]
                 },
                 "sessions_params": {
                   "n": 10,
                   "max_active_user_id": 5,
                   "seed": 1,
                   "time_units": 1,
                   "tiers": [
                     {"max_followers": 1000, "session_minutes": 240}
                   ]
                 },
                 "follows_params": {
                   "n": 10,
                   "max_active_user_id": 5,
                   "seed": 1,
                   "time_units": 1,
                   "tiers": [
                     {"max_followers": 1000, "follows_per_time_unit": 0.25}
                   ]
                 }
               }
               """)

      assert params.posts_params.n == 10
      assert params.sessions_params.n == 10
      assert params.follows_params.n == 10
    end

    test "supports optional sections" do
      assert {:ok, %SimulationPlanParams{} = params} = SimulationPlanParams.load("{}")
      assert is_nil(params.posts_params)
      assert is_nil(params.sessions_params)
      assert is_nil(params.follows_params)
    end
  end

  describe "load_file/1" do
    @tag :tmp_dir
    test "reads unified json from disk", %{tmp_dir: tmp_dir} do
      path = write_file!(tmp_dir, "simulation-plan-params", "{}")
      assert {:ok, %SimulationPlanParams{}} = SimulationPlanParams.load_file(path)
    end

    test "returns an error with file path when file does not exist" do
      path = "missing-simulation-plan-params.json"
      error_msg = "cannot read simulation plan params file at #{path}"

      assert {:error, ^error_msg} = SimulationPlanParams.load_file(path)
    end
  end

  defp write_file!(tmp_dir, prefix, content) do
    path = Path.join(tmp_dir, "#{prefix}-#{System.unique_integer([:positive])}.json")
    File.write!(path, content)
    path
  end
end
