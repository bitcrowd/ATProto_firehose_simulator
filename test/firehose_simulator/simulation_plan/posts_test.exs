defmodule FirehoseSimulator.SimulationPlan.PostsTest do
  use ExUnit.Case, async: false

  alias FirehoseSimulator.SimulationPlan.Posts
  alias FirehoseSimulator.SimulationPlan.PostsParams
  alias FirehoseSimulator.SimulationPlan.CSV

  @config %PostsParams{
    n: 100,
    max_active_user_id: 2,
    seed: 42,
    time_units: 1,
    path: "posts.csv",
    tiers: [%FirehoseSimulator.SimulationPlan.PostTier{max_followers: 1_000, posts_per_day: 1.0}]
  }

  test "generate/1 returns an in-memory plan struct" do
    plan = Posts.generate(@config)

    assert %Posts{posts: posts} = plan
    assert length(posts) == 2
    assert Enum.all?(posts, &is_integer(&1.offset_ms))
    assert posts |> Enum.map(& &1.user_id) |> Enum.sort() == [1, 2]
  end

  @tag :tmp_dir
  test "CSV.write/2 and CSV.load/2 round-trip the generated posts", %{tmp_dir: tmp_dir} do
    plan = Posts.generate(@config)
    path = Path.join(tmp_dir, "posts.csv")

    assert :ok = CSV.write(plan, path)

    assert File.read!(path) ==
             "offset_ms,user_id\n" <>
               Enum.map_join(plan.posts, "", fn post ->
                 "#{post.offset_ms},#{post.user_id}\n"
               end)

    assert {:ok, loaded_posts} = CSV.load(:posts, path)
    assert loaded_posts == plan.posts
  end

  test "CSV.load/2 returns an error for missing csv" do
    path = "does-not-exist-posts.csv"
    error_msg = "cannot read posts csv at #{path}"

    assert {:error, ^error_msg} = CSV.load(:posts, path)
  end
end
