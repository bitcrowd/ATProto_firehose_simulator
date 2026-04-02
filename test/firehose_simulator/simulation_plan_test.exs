defmodule FirehoseSimulator.SimulationPlanTest do
  use ExUnit.Case, async: false

  alias FirehoseSimulator.SimulationPlan
  alias FirehoseSimulator.SimulationPlan.Follows
  alias FirehoseSimulator.SimulationPlan.Posts
  alias FirehoseSimulator.SimulationPlan.Sessions

  describe "load_from_json/1" do
    @tag :tmp_dir
    test "loads params from json files and generates posts, sessions, and follows plans",
         %{tmp_dir: tmp_dir} do
      posts_path =
        write_file!(
          tmp_dir,
          "posts",
          """
          {
            "n": 10,
            "max_active_user_id": 5,
            "seed": 1,
            "time_units": 1,
            "tiers": [
              {"max_followers": 1000, "posts_per_day": 0.25}
            ]
          }
          """
        )

      sessions_path =
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

      follows_path =
        write_file!(
          tmp_dir,
          "follows",
          """
          {
            "n": 10,
            "max_active_user_id": 5,
            "seed": 1,
            "time_units": 1,
            "tiers": [
              {"max_followers": 1000, "follows_per_day": 0.25}
            ]
          }
          """
        )

      assert {:ok,
              %SimulationPlan{
                posts_plan: %Posts{posts: posts},
                sessions_plan: %Sessions{sessions: sessions},
                follows_plan: %Follows{follows: follows}
              }} =
               SimulationPlan.load_from_json(
                 posts: posts_path,
                 sessions: sessions_path,
                 follows: follows_path
               )

      assert length(sessions) == 5
      assert is_list(posts)
      assert is_list(follows)
    end

    test "returns nil for sections without a path" do
      assert {:ok, %SimulationPlan{posts_plan: nil, sessions_plan: nil, follows_plan: nil}} =
               SimulationPlan.load_from_json([])
    end
  end

  defp write_file!(tmp_dir, prefix, content) do
    path = Path.join(tmp_dir, "#{prefix}-#{System.unique_integer([:positive])}.json")
    File.write!(path, content)
    path
  end
end
