defmodule FirehoseSimulator.SimulationPlan.Params.PostsParamsTest do
  use ExUnit.Case, async: false

  alias FirehoseSimulator.SimulationPlan.Params.PostsParams

  describe "load/1" do
    test "returns a posts struct for valid json" do
      assert {:ok, %PostsParams{} = posts} =
               PostsParams.load("""
               {
                 "n": 1000000,
                 "max_active_user_id": 5000,
                 "follower_density": 2.0,
                 "seed": 42,
                 "time_units": 1,
                 "tiers": [
                   {"max_followers": 1000, "posts_per_day": 0.25},
                   {"max_followers": 10000, "posts_per_day": 10},
                   {"max_followers": 1000000, "posts_per_day": 3}
                 ]
               }
               """)

      assert posts.follower_density == 2.0
      assert Enum.map(posts.tiers, & &1.posts_per_day) == [0.25, 10.0, 3.0]
    end

    test "defaults follower_density to 1.0 when omitted" do
      assert {:ok, %PostsParams{} = posts} =
               PostsParams.load("""
               {
                 "n": 10,
                 "max_active_user_id": 5,
                 "seed": 1,
                 "time_units": 1,
                 "tiers": [
                   {"max_followers": 1000, "posts_per_day": 0.25}
                 ]
               }
               """)

      assert posts.follower_density == 1.0
    end

    test "returns an error for malformed json" do
      error_msg = "invalid posts json"

      assert {:error, ^error_msg} = PostsParams.load("{bad json")
    end

    test "returns an error for malformed json object type" do
      error_msg = "invalid posts json: expected json object"

      assert {:error, ^error_msg} = PostsParams.load("[]")
    end
  end

  describe "load!/1" do
    test "returns the posts config on success" do
      assert %PostsParams{} =
               PostsParams.load!("""
               {
                 "n": 10,
                 "max_active_user_id": 5,
                 "seed": 1,
                 "time_units": 1,
                 "tiers": [
                   {"max_followers": 1000, "posts_per_day": 0.25}
                 ]
               }
               """)
    end
  end

  describe "load_file/1" do
    @tag :tmp_dir
    test "reads posts json from disk", %{tmp_dir: tmp_dir} do
      path =
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

      assert {:ok, %PostsParams{}} = PostsParams.load_file(path)
    end

    test "returns an error with file path when file does not exist" do
      path = "missing-posts.json"
      error_msg = "cannot read posts file at #{path}"

      assert {:error, ^error_msg} = PostsParams.load_file(path)
    end
  end

  defp write_file!(tmp_dir, prefix, content) do
    path = Path.join(tmp_dir, "#{prefix}-#{System.unique_integer([:positive])}.json")
    File.write!(path, content)
    path
  end
end
