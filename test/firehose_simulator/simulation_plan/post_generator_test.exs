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

    assert %PostGenerator{config: @config, posts: posts} = plan
    assert length(posts) == 2
    assert Enum.all?(posts, &is_integer(&1.offset_ms))
    assert posts |> Enum.map(& &1.user_id) |> Enum.sort() == [1, 2]
  end

  @tag :tmp_dir
  test "write_to_csv/2 writes the generated posts", %{tmp_dir: tmp_dir} do
    plan = PostGenerator.generate(@config)
    path = Path.join(tmp_dir, "posts.csv")

    assert :ok = PostGenerator.write_to_csv(plan, path)

    assert File.read!(path) ==
             "offset_ms,user_id\n" <>
               Enum.map_join(plan.posts, "", fn post ->
                 "#{post.offset_ms},#{post.user_id}\n"
               end)
  end
end
