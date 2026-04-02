defmodule FirehoseSimulator.SimulationPlan.Posts do
  @moduledoc """
  Generates a deterministic in-memory posts plan from a follower graph configuration.

  Posts are distributed at random offsets throughout each simulated time unit,
  independent of session schedules. Uses its own RNG seed so changing
  post config does not affect session generation.

  ## Example

      FirehoseSimulator.SimulationPlan.Posts.generate(%PostsParams{...})
  """

  alias FirehoseSimulator.SimulationPlan.FollowerGraph
  alias FirehoseSimulator.SimulationPlan.Params.PostsParams

  @default_unit_duration_ms 86_400_000

  @type post :: %{
          offset_ms: non_neg_integer(),
          user_id: pos_integer()
        }

  @type t :: %__MODULE__{
          posts: [post()]
        }

  defstruct posts: []

  @doc """
  Generate an in-memory posts plan from a `%PostsParams{}` config.
  """
  def generate(%PostsParams{} = config) do
    :rand.seed(:exsss, {config.seed, config.seed, config.seed})

    posts =
      build_posts(
        config.max_active_user_id,
        config.n,
        config.time_units,
        config.tiers,
        @default_unit_duration_ms
      )

    posts = Enum.sort_by(posts, &elem(&1, 0))
    posts = Enum.map(posts, &post_from_tuple/1)

    %__MODULE__{posts: posts}
  end

  defp build_posts(max_active_user_id, n, time_units, tiers, unit_duration_ms) do
    for unit <- 0..(time_units - 1), user_id <- 1..max_active_user_id, reduce: [] do
      acc ->
        unit_offset = unit * unit_duration_ms
        tier = lookup_tier(user_id, n, tiers)
        new_posts = generate_posts(tier.posts_per_day, user_id, unit_offset, unit_duration_ms)
        new_posts ++ acc
    end
  end

  defp generate_posts(posts_per_day, user_id, unit_offset, unit_duration_ms)
       when posts_per_day < 1.0 do
    if :rand.uniform() < posts_per_day do
      [{unit_offset + :rand.uniform(unit_duration_ms) - 1, user_id}]
    else
      []
    end
  end

  defp generate_posts(posts_per_day, user_id, unit_offset, unit_duration_ms) do
    count = trunc(posts_per_day)
    fractional = posts_per_day - count

    base_posts =
      for _ <- 1..count do
        {unit_offset + :rand.uniform(unit_duration_ms) - 1, user_id}
      end

    extra =
      if fractional > 0 and :rand.uniform() < fractional do
        [{unit_offset + :rand.uniform(unit_duration_ms) - 1, user_id}]
      else
        []
      end

    base_posts ++ extra
  end

  defp lookup_tier(user_id, n, tiers) do
    follower_count = FollowerGraph.follower_count(user_id, n)

    Enum.find(tiers, List.last(tiers), fn tier ->
      follower_count <= tier.max_followers
    end)
  end

  defp post_from_tuple({offset_ms, user_id}) do
    %{offset_ms: offset_ms, user_id: user_id}
  end
end
