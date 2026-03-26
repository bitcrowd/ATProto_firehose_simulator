defmodule FirehoseSimulator.FollowerGraph do
  @moduledoc """
  Generates a deterministic follower graph for `n` users with a power-law distribution.

  User IDs are integers 1..n, ordered by follower count descending:
  user 1 has the most followers (n-1), user n has zero.

  The follower count formula is `max(0, round(n / user_id) - 1)`.
  Followers are assigned deterministically: user x gets followers {x+1, ..., x+F(x)}.
  """

  @doc """
  Generates the full follower graph for `n` users.

  Returns `{:ok, graph, follows_count}` where `graph` is a map
  `%{user_id => [follower_ids]}` and `follows_count` is the total number
  of follow edges.

  ## Examples

      iex> {:ok, graph, 7} = FirehoseSimulator.FollowerGraph.generate(5)
      iex> graph
      %{1 => [2, 3, 4, 5], 2 => [3, 4], 3 => [4], 4 => [], 5 => []}
  """
  def generate(n, start_id \\ 1) when is_integer(n) and n >= 1 do
    id_range = start_id..(start_id + n - 1)
    base = Map.new(id_range, fn user_id -> {user_id, []} end)

    {graph, follows_count} =
      Enum.reduce(Enum.with_index(id_range, 1), {base, 0}, fn {user_id, rank}, {graph, total} ->
        count = follower_count(rank, n)

        followers = for fid <- (user_id + 1)..(user_id + count)//1, do: fid

        {Map.put(graph, user_id, followers), total + count}
      end)

    {:ok, graph, follows_count}
  end

  @doc """
  Returns the follower count for a single user_id given n total users.

  ## Examples

      iex> FirehoseSimulator.FollowerGraph.follower_count(1, 5)
      4

      iex> FirehoseSimulator.FollowerGraph.follower_count(5, 5)
      0
  """
  def follower_count(rank, n) when is_integer(rank) and rank >= 1 and is_integer(n) and n >= 1 do
    max(0, round(n / rank) - 1)
  end
end
