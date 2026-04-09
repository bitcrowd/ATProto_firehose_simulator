defmodule FirehoseSimulator.BaseData.FollowerGraph do
  @moduledoc """
  Generates a deterministic follower graph for `n` users with a power-law distribution.

  User IDs are integers 1..n, ordered by follower count descending:
  user 1 has the most followers (n-1), user n has zero.

  The follower count formula is `max(0, round((n / user_id) * follower_density) - 1)`.
  Followers are assigned deterministically: user x gets followers {x+1, ..., x+F(x)}.
  """

  @doc """
  Generates the full follower graph for `n` users.

  Returns `{:ok, graph, follows_count}` where `graph` is a map
  `%{user_id => [follower_ids]}` and `follows_count` is the total number
  of follow edges.

  ## Examples

      iex> {:ok, graph, 7} = FirehoseSimulator.BaseData.FollowerGraph.generate(5)
      iex> graph
      %{1 => [2, 3, 4, 5], 2 => [3, 4], 3 => [4], 4 => [], 5 => []}

      iex> {:ok, graph, 10} = FirehoseSimulator.BaseData.FollowerGraph.generate(5, follower_density: 2.0)
      iex> graph[2]
      [3, 4, 5]
  """
  def generate(n) when is_integer(n) and n >= 1 do
    generate(n, [])
  end

  def generate(n, start_id)
      when is_integer(n) and n >= 1 and is_integer(start_id) and start_id >= 1 do
    generate(n, start_id: start_id)
  end

  def generate(n, opts) when is_integer(n) and n >= 1 and is_list(opts) do
    start_id = Keyword.get(opts, :start_id, 1)
    follower_density = Keyword.get(opts, :follower_density, 1.0)

    id_range = start_id..(start_id + n - 1)
    base = Map.new(id_range, fn user_id -> {user_id, []} end)

    {graph, follows_count} =
      Enum.reduce(Enum.with_index(id_range, 1), {base, 0}, fn {user_id, rank}, {graph, total} ->
        count = follower_count(rank, n, follower_density)

        followers = for fid <- (user_id + 1)..(user_id + count)//1, do: fid

        {Map.put(graph, user_id, followers), total + count}
      end)

    {:ok, graph, follows_count}
  end

  @doc """
  Returns the follower count for a single user_id given n total users.

  ## Examples

      iex> FirehoseSimulator.BaseData.FollowerGraph.follower_count(1, 5)
      4

      iex> FirehoseSimulator.BaseData.FollowerGraph.follower_count(5, 5)
      0

      iex> FirehoseSimulator.BaseData.FollowerGraph.follower_count(2, 5, 2.0)
      4
  """
  def follower_count(rank, n, follower_density \\ 1.0)
      when is_integer(rank) and rank >= 1 and is_integer(n) and n >= 1 and
             is_number(follower_density) and
             follower_density > 0 do
    requested_count = max(0, round(n / rank * follower_density) - 1)
    max_count = n - rank
    min(requested_count, max_count)
  end
end
