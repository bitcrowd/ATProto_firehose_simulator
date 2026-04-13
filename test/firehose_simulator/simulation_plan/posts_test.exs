defmodule FirehoseSimulator.SimulationPlan.PostsTest do
  use ExUnit.Case, async: false

  alias FirehoseSimulator.SimulationPlan.Posts
  alias FirehoseSimulator.SimulationPlan.Params.PostsParams

  @config %PostsParams{
    num_users: 100,
    max_active_user_id: 2,
    follower_density: 1.0,
    tiers: [
      %FirehoseSimulator.SimulationPlan.Params.PostTier{
        max_followers: 1_000,
        posts_per_time_unit: 1.0
      }
    ]
  }

  test "generate/4 returns an in-memory posts list" do
    posts = Posts.generate(@config, 42, 1)

    assert length(posts) == 2
    assert Enum.all?(posts, &is_integer(&1.offset_ms))
    assert posts |> Enum.map(& &1.user_id) |> Enum.sort() == [1, 2]
  end

  test "generate/4 uses follower_density for tier matching" do
    config = %PostsParams{
      num_users: 10,
      max_active_user_id: 2,
      follower_density: 1.0,
      tiers: [
        %FirehoseSimulator.SimulationPlan.Params.PostTier{
          max_followers: 6,
          posts_per_time_unit: 0.0
        },
        %FirehoseSimulator.SimulationPlan.Params.PostTier{
          max_followers: 100,
          posts_per_time_unit: 1.0
        }
      ]
    }

    dense_config = %{config | follower_density: 2.0}

    assert length(Posts.generate(config, 42, 1)) == 1
    assert length(Posts.generate(dense_config, 42, 1)) == 2
  end

  test "generate/4 uses the provided time unit duration" do
    posts = Posts.generate(@config, 42, 1, 1_000)

    assert Enum.all?(posts, &(&1.offset_ms < 1_000))
  end
end
