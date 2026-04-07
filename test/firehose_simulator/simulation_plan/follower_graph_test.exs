defmodule FirehoseSimulator.SimulationPlan.FollowerGraphTest do
  use ExUnit.Case, async: true

  alias FirehoseSimulator.SimulationPlan.FollowerGraph

  test "generates the expected graph for a small user set" do
    assert {:ok, graph, 7} = FollowerGraph.generate(5)

    assert graph == %{
             1 => [2, 3, 4, 5],
             2 => [3, 4],
             3 => [4],
             4 => [],
             5 => []
           }
  end

  test "offsets generated user ids when a start id is provided" do
    assert {:ok, graph, 4} = FollowerGraph.generate(4, 10)

    assert graph == %{
             10 => [11, 12, 13],
             11 => [12],
             12 => [],
             13 => []
           }
  end

  test "supports follower_density option while preserving shape" do
    assert {:ok, graph, 10} = FollowerGraph.generate(5, follower_density: 2.0)

    assert graph == %{
             1 => [2, 3, 4, 5],
             2 => [3, 4, 5],
             3 => [4, 5],
             4 => [5],
             5 => []
           }
  end
end
