defmodule FirehoseSimulator.SimulationPlan.FollowsGeneratorTest do
  use ExUnit.Case, async: false

  alias FirehoseSimulator.SimulationPlan.Follows
  alias FirehoseSimulator.SimulationPlan.FollowsGenerator

  @config %Follows{
    n: 100,
    max_active_user_id: 2,
    seed: 42,
    time_units: 1,
    path: "follows.csv",
    tiers: [
      %FirehoseSimulator.SimulationPlan.FollowTier{max_followers: 1_000, follows_per_day: 1.0}
    ]
  }

  test "generate/1 returns an in-memory plan struct" do
    plan = FollowsGenerator.generate(@config)

    assert %FollowsGenerator{config: @config, follows: follows} = plan
    assert length(follows) == 2
    assert Enum.all?(follows, &is_integer(&1.offset_ms))
    assert follows |> Enum.map(& &1.actor_id) |> Enum.sort() == [1, 2]
    assert Enum.all?(follows, &is_integer(&1.subject_id))
  end

  @tag :tmp_dir
  test "write_to_csv/2 writes the generated follows", %{tmp_dir: tmp_dir} do
    plan = FollowsGenerator.generate(@config)
    path = Path.join(tmp_dir, "follows.csv")

    assert :ok = FollowsGenerator.write_to_csv(plan, path)

    assert File.read!(path) ==
             "offset_ms,actor_id,subject_id\n" <>
               Enum.map_join(plan.follows, "", fn follow ->
                 "#{follow.offset_ms},#{follow.actor_id},#{follow.subject_id}\n"
               end)
  end
end
