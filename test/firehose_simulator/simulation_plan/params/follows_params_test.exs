defmodule FirehoseSimulator.SimulationPlan.Params.FollowsParamsTest do
  use ExUnit.Case, async: false

  alias FirehoseSimulator.SimulationPlan.Params.FollowsParams

  describe "load/1" do
    test "returns a follows struct for valid json" do
      assert {:ok, %FollowsParams{} = follows} =
               FollowsParams.load("""
               {
                 "num_users": 1000000,
                 "max_active_user_id": 5000,
                 "follower_density": 2.0,
                 "tiers": [
                   {"max_followers": 1000, "follows_per_time_unit": 0.25},
                   {"max_followers": 10000, "follows_per_time_unit": 10},
                   {"max_followers": 1000000, "follows_per_time_unit": 3}
                 ]
               }
               """)

      assert follows.follower_density == 2.0
      assert Enum.map(follows.tiers, & &1.follows_per_time_unit) == [0.25, 10.0, 3.0]
    end

    test "defaults follower_density to 1.0 when omitted" do
      assert {:ok, %FollowsParams{} = follows} =
               FollowsParams.load("""
               {
                 "num_users": 10,
                 "max_active_user_id": 5,
                 "tiers": [
                   {"max_followers": 1000, "follows_per_time_unit": 0.25}
                 ]
               }
               """)

      assert follows.follower_density == 1.0
    end

    test "returns an error for malformed json" do
      error_msg = "invalid follows json"

      assert {:error, ^error_msg} = FollowsParams.load("{bad json")
    end

    test "requires at least one tier" do
      assert {:error, message} =
               FollowsParams.load("""
               {
                 "num_users": 1000000,
                 "max_active_user_id": 5000,
                 "tiers": []
               }
               """)

      assert String.contains?(message, "invalid follows config:")
      assert String.contains?(message, "tiers")
    end
  end

  describe "load!/1" do
    test "returns the follows config on success" do
      assert %FollowsParams{} =
               FollowsParams.load!("""
               {
                 "num_users": 10,
                 "max_active_user_id": 5,
                 "tiers": [
                   {"max_followers": 1000, "follows_per_time_unit": 0.25}
                 ]
               }
               """)
    end
  end

  describe "load_file/1" do
    @tag :tmp_dir
    test "reads follows json from disk", %{tmp_dir: tmp_dir} do
      path =
        write_file!(
          tmp_dir,
          "follows",
          """
          {
            "num_users": 10,
            "max_active_user_id": 5,
            "tiers": [
              {"max_followers": 1000, "follows_per_time_unit": 0.25}
            ]
          }
          """
        )

      assert {:ok, %FollowsParams{}} = FollowsParams.load_file(path)
    end

    test "returns an error with file path when file does not exist" do
      path = "missing-follows.json"
      error_msg = "cannot read follows file at #{path}"

      assert {:error, ^error_msg} = FollowsParams.load_file(path)
    end
  end

  defp write_file!(tmp_dir, prefix, content) do
    path = Path.join(tmp_dir, "#{prefix}-#{System.unique_integer([:positive])}.json")
    File.write!(path, content)
    path
  end
end
