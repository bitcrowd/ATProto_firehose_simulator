defmodule FirehoseSimulator.SimulationPlanTest do
  use ExUnit.Case, async: false

  alias FirehoseSimulator.SimulationPlan

  describe "load_from_json/1" do
    @tag :tmp_dir
    test "loads unified params json and generates posts, sessions, and follows plans",
         %{tmp_dir: tmp_dir} do
      params_path =
        write_file!(
          tmp_dir,
          "simulation-plan-params",
          """
          {
            "posts_params": {
              "n": 10,
              "max_active_user_id": 5,
              "seed": 1,
              "time_units": 1,
              "tiers": [
                {"max_followers": 1000, "posts_per_day": 0.25}
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
                {"max_followers": 1000, "follows_per_day": 0.25}
              ]
            }
          }
          """
        )

      assert {:ok,
              %SimulationPlan{
                posts: posts,
                sessions: sessions,
                follows: follows
              }} =
               SimulationPlan.load_from_json(simulation_plan_params: params_path)

      assert length(sessions) == 5
      assert is_list(posts)
      assert is_list(follows)
    end

    test "returns nil for sections without a path" do
      assert {:ok, %SimulationPlan{posts: nil, sessions: nil, follows: nil}} =
               SimulationPlan.load_from_json([])
    end
  end

  defp write_file!(tmp_dir, prefix, content) do
    path = Path.join(tmp_dir, "#{prefix}-#{System.unique_integer([:positive])}.json")
    File.write!(path, content)
    path
  end
end
