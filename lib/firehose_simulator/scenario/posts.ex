defmodule FirehoseSimulator.Scenario.Posts do
  @moduledoc """
  Generates a deterministic in-memory posts plan from a follower graph configuration.

  Posts are distributed at random offsets throughout each simulated time unit,
  independent of session schedules.

  ## Example

      FirehoseSimulator.Scenario.Posts.generate(%PostsParams{...})
  """

  alias FirehoseSimulator.BaseData.FollowerGraph
  alias FirehoseSimulator.Scenario.Params.PostsParams

  @default_unit_duration_ms 86_400_000

  @type post :: %{
          offset_ms: non_neg_integer(),
          user_id: pos_integer()
        }

  @type t :: [post()]

  @doc """
  Generate an in-memory posts plan from a `%PostsParams{}` config.
  """
  def generate(
        %PostsParams{} = config,
        seed,
        time_units,
        unit_duration_ms \\ @default_unit_duration_ms
      )
      when is_integer(seed) and is_integer(time_units) and time_units > 0 and
             is_integer(unit_duration_ms) and unit_duration_ms > 0 do
    :rand.seed(:exsss, {seed, seed, seed})

    posts =
      build_posts(
        config.max_active_user_id,
        config.num_users,
        config.follower_density,
        time_units,
        config.tiers,
        unit_duration_ms
      )

    posts = Enum.sort_by(posts, &elem(&1, 0))
    Enum.map(posts, &post_from_tuple/1)
  end

  defp build_posts(
         max_active_user_id,
         num_users,
         follower_density,
         time_units,
         tiers,
         unit_duration_ms
       ) do
    for unit <- 0..(time_units - 1), user_id <- 1..max_active_user_id, reduce: [] do
      acc ->
        unit_offset = unit * unit_duration_ms
        tier = lookup_tier(user_id, num_users, tiers, follower_density)

        new_posts =
          generate_posts(tier.posts_per_time_unit, user_id, unit_offset, unit_duration_ms)

        new_posts ++ acc
    end
  end

  defp generate_posts(posts_per_time_unit, user_id, unit_offset, unit_duration_ms)
       when posts_per_time_unit < 1.0 do
    if :rand.uniform() < posts_per_time_unit do
      [{unit_offset + :rand.uniform(unit_duration_ms) - 1, user_id}]
    else
      []
    end
  end

  defp generate_posts(posts_per_time_unit, user_id, unit_offset, unit_duration_ms) do
    count = trunc(posts_per_time_unit)
    fractional = posts_per_time_unit - count

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

  defp lookup_tier(user_id, num_users, tiers, follower_density) do
    follower_count = FollowerGraph.follower_count(user_id, num_users, follower_density)

    Enum.find(tiers, List.last(tiers), fn tier ->
      follower_count <= tier.max_followers
    end)
  end

  defp post_from_tuple({offset_ms, user_id}) do
    %{offset_ms: offset_ms, user_id: user_id}
  end
end
