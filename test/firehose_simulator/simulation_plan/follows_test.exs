defmodule FirehoseSimulator.SimulationPlan.FollowsTest do
  use ExUnit.Case, async: false

  alias FirehoseSimulator.SimulationPlan.Follows
  alias FirehoseSimulator.SimulationPlan.Params.FollowsParams

  @config %FollowsParams{
    n: 100,
    max_active_user_id: 2,
    seed: 42,
    time_units: 1,
    tiers: [
      %FirehoseSimulator.SimulationPlan.Params.FollowTier{
        max_followers: 1_000,
        follows_per_day: 1.0
      }
    ]
  }

  test "generate/1 returns an in-memory follows list" do
    follows = Follows.generate(@config)

    assert length(follows) == 2
    assert Enum.all?(follows, &is_integer(&1.offset_ms))
    assert follows |> Enum.map(& &1.actor_id) |> Enum.sort() == [1, 2]
    assert Enum.all?(follows, &is_integer(&1.subject_id))
  end
end
