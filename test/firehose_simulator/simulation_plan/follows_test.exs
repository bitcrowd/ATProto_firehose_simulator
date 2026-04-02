defmodule FirehoseSimulator.SimulationPlan.FollowsTest do
  use ExUnit.Case, async: false

  alias FirehoseSimulator.SimulationPlan.Follows
  alias FirehoseSimulator.SimulationPlan.Params.FollowsParams
  alias FirehoseSimulator.SimulationPlan.CSV

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

  test "generate/1 returns an in-memory plan struct" do
    plan = Follows.generate(@config)

    assert %Follows{follows: follows} = plan
    assert length(follows) == 2
    assert Enum.all?(follows, &is_integer(&1.offset_ms))
    assert follows |> Enum.map(& &1.actor_id) |> Enum.sort() == [1, 2]
    assert Enum.all?(follows, &is_integer(&1.subject_id))
  end

  @tag :tmp_dir
  test "CSV.write/2 and CSV.load/2 round-trip the generated follows", %{tmp_dir: tmp_dir} do
    plan = Follows.generate(@config)
    path = Path.join(tmp_dir, "follows.csv")

    assert :ok = CSV.write(plan, path)

    assert File.read!(path) ==
             "offset_ms,actor_id,subject_id\n" <>
               Enum.map_join(plan.follows, "", fn follow ->
                 "#{follow.offset_ms},#{follow.actor_id},#{follow.subject_id}\n"
               end)

    assert {:ok, loaded_follows} = CSV.load(:follows, path)

    assert loaded_follows == plan.follows
  end

  test "CSV.load/2 returns an error for missing csv" do
    path = "does-not-exist-follows.csv"
    error_msg = "cannot read follows csv at #{path}"

    assert {:error, ^error_msg} = CSV.load(:follows, path)
  end
end
