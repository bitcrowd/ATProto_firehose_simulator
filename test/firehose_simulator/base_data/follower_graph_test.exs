defmodule FirehoseSimulator.BaseData.FollowerGraphTest do
  use ExUnit.Case, async: true

  alias FirehoseSimulator.BaseData.FollowerGraph

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

  test "streams follows in deterministic export order" do
    follows =
      FollowerGraph.stream_follows(5)
      |> Enum.map(fn %{actor_id: actor_id, subject_id: subject_id} -> {actor_id, subject_id} end)

    assert follows == [{2, 1}, {3, 1}, {4, 1}, {5, 1}, {3, 2}, {4, 2}, {4, 3}]
  end

  test "streamed follows count matches generated graph count" do
    assert {:ok, _graph, follows_count} = FollowerGraph.generate(5, follower_density: 2.0)

    streamed_count =
      FollowerGraph.stream_follows(5, follower_density: 2.0)
      |> Enum.count()

    assert streamed_count == follows_count
  end

  test "streams follows with start id offset" do
    follows =
      FollowerGraph.stream_follows(4, start_id: 10)
      |> Enum.map(fn %{actor_id: actor_id, subject_id: subject_id} -> {actor_id, subject_id} end)

    assert follows == [{11, 10}, {12, 10}, {13, 10}, {12, 11}]
  end

  test "streams follow batches grouped by subject" do
    batches =
      FollowerGraph.stream_follow_batches_by_subject(5)
      |> Enum.map(fn batch ->
        Enum.map(batch, fn %{actor_id: actor_id, subject_id: subject_id} ->
          {actor_id, subject_id}
        end)
      end)

    assert batches == [
             [{2, 1}, {3, 1}, {4, 1}, {5, 1}],
             [{3, 2}, {4, 2}],
             [{4, 3}]
           ]
  end
end
