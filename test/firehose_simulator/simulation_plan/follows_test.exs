defmodule FirehoseSimulator.SimulationPlan.FollowsTest do
  use ExUnit.Case, async: false

  alias FirehoseSimulator.SimulationPlan.Follows
  alias FirehoseSimulator.SimulationPlan.Params.FollowsParams

  @config %FollowsParams{
    num_users: 100,
    max_active_user_id: 2,
    follower_density: 1.0,
    tiers: [
      %FirehoseSimulator.SimulationPlan.Params.FollowTier{
        max_followers: 1_000,
        follows_per_time_unit: 1.0
      }
    ]
  }

  test "generate/4 returns an in-memory follows list" do
    follows = Follows.generate(@config, 42, 1)

    assert length(follows) == 2
    assert Enum.all?(follows, &is_integer(&1.offset_ms))
    assert follows |> Enum.map(& &1.actor_id) |> Enum.sort() == [1, 2]
    assert Enum.all?(follows, &is_integer(&1.subject_id))
  end

  test "generate/4 uses follower_density for tier matching" do
    config = %FollowsParams{
      num_users: 10,
      max_active_user_id: 2,
      follower_density: 1.0,
      tiers: [
        %FirehoseSimulator.SimulationPlan.Params.FollowTier{
          max_followers: 6,
          follows_per_time_unit: 0.0
        },
        %FirehoseSimulator.SimulationPlan.Params.FollowTier{
          max_followers: 100,
          follows_per_time_unit: 1.0
        }
      ]
    }

    dense_config = %{config | follower_density: 2.0}

    assert length(Follows.generate(config, 42, 1)) == 1
    assert length(Follows.generate(dense_config, 42, 1)) == 2
  end

  test "generate/4 uses the provided time unit duration" do
    follows = Follows.generate(@config, 42, 1, 1_000)

    assert Enum.all?(follows, &(&1.offset_ms < 1_000))
  end
end
