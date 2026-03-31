defmodule FirehoseSimulator.SimulationPlan.PostGeneratorTest do
  use ExUnit.Case, async: false

  alias FirehoseSimulator.SimulationPlan.PostGenerator
  alias FirehoseSimulator.SimulationPlan.Posts

  @config %Posts{
    n: 100,
    max_active_user_id: 2,
    seed: 42,
    time_units: 1,
    path: "posts.csv",
    tiers: [%FirehoseSimulator.SimulationPlan.PostTier{max_followers: 1_000, posts_per_day: 1.0}]
  }

  test "generate/1 returns an in-memory plan struct" do
    plan = PostGenerator.generate(@config)

    assert %PostGenerator{posts: posts} = plan
    assert length(posts) == 2
    assert Enum.all?(posts, &is_integer(&1.offset_ms))
    assert posts |> Enum.map(& &1.user_id) |> Enum.sort() == [1, 2]
  end

  @tag :tmp_dir
  test "write_to_csv/2 and load_from_csv/1 round-trip the generated posts", %{tmp_dir: tmp_dir} do
    plan = PostGenerator.generate(@config)
    path = Path.join(tmp_dir, "posts.csv")

    assert :ok = PostGenerator.write_to_csv(plan, path)

    assert File.read!(path) ==
             "offset_ms,user_id\n" <>
               Enum.map_join(plan.posts, "", fn post ->
                 "#{post.offset_ms},#{post.user_id}\n"
               end)

    assert {:ok, %PostGenerator{posts: loaded_posts}} = PostGenerator.load_from_csv(path)
    assert loaded_posts == plan.posts
  end

  test "load_from_csv/1 returns an error for missing csv" do
    path = "does-not-exist-posts.csv"
    error_msg = "cannot read posts csv at #{path}"

    assert {:error, ^error_msg} = PostGenerator.load_from_csv(path)
  end
end
