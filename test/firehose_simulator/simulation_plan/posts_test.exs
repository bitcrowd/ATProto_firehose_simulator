defmodule FirehoseSimulator.SimulationPlan.PostsTest do
  use ExUnit.Case, async: false

  alias FirehoseSimulator.SimulationPlan.Posts
  alias FirehoseSimulator.SimulationPlan.Params.PostsParams

  @config %PostsParams{
    n: 100,
    max_active_user_id: 2,
    seed: 42,
    time_units: 1,
    tiers: [
      %FirehoseSimulator.SimulationPlan.Params.PostTier{max_followers: 1_000, posts_per_day: 1.0}
    ]
  }

  test "generate/1 returns an in-memory posts list" do
    posts = Posts.generate(@config)

    assert length(posts) == 2
    assert Enum.all?(posts, &is_integer(&1.offset_ms))
    assert posts |> Enum.map(& &1.user_id) |> Enum.sort() == [1, 2]
  end
end
