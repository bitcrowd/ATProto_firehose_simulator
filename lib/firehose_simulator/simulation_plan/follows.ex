defmodule FirehoseSimulator.SimulationPlan.Follows do
  @moduledoc """
  Generates a deterministic in-memory follows plan from a follower graph configuration.

  Follow events are distributed at random offsets throughout each simulated time unit,
  independent of session schedules. Uses its own RNG seed so changing
  follow config does not affect session generation.

  ## Example

      FirehoseSimulator.SimulationPlan.Follows.generate(%FollowsParams{...})
  """

  alias FirehoseSimulator.BaseData.FollowerGraph
  alias FirehoseSimulator.SimulationPlan.Params.FollowsParams

  @default_unit_duration_ms 86_400_000

  @type follow :: %{
          offset_ms: non_neg_integer(),
          actor_id: pos_integer(),
          subject_id: pos_integer()
        }

  @type t :: [follow()]

  @doc """
  Generate an in-memory follows plan from a `%FollowsParams{}` config.
  """
  def generate(%FollowsParams{} = config) do
    generate(config, @default_unit_duration_ms)
  end

  @doc """
  Generate an in-memory follows plan from a `%FollowsParams{}` config and explicit
  time unit duration in milliseconds.
  """
  def generate(%FollowsParams{} = config, unit_duration_ms)
      when is_integer(unit_duration_ms) and unit_duration_ms > 0 do
    :rand.seed(:exsss, {config.seed, config.seed, config.seed})

    follows =
      build_follows(
        config.max_active_user_id,
        config.num_users,
        config.follower_density,
        config.time_units,
        config.tiers,
        unit_duration_ms
      )

    follows = Enum.sort_by(follows, fn {offset, seq, _actor, _subject} -> {offset, seq} end)
    Enum.map(follows, &follow_from_tuple/1)
  end

  defp build_follows(
         max_active_user_id,
         num_users,
         follower_density,
         time_units,
         tiers,
         unit_duration_ms
       ) do
    {events, _next_seq} =
      for unit <- 0..(time_units - 1), user_id <- 1..max_active_user_id, reduce: {[], 0} do
        {acc_events, seq} ->
          unit_offset = unit * unit_duration_ms
          tier = lookup_tier(user_id, num_users, tiers, follower_density)

          {new_events, next_seq} =
            generate_follows(
              tier.follows_per_time_unit,
              user_id,
              num_users,
              unit_offset,
              unit_duration_ms,
              seq
            )

          {new_events ++ acc_events, next_seq}
      end

    events
  end

  defp generate_follows(
         follows_per_time_unit,
         user_id,
         num_users,
         unit_offset,
         unit_duration_ms,
         seq
       )
       when follows_per_time_unit < 1.0 do
    if :rand.uniform() < follows_per_time_unit do
      build_follow_event(user_id, num_users, unit_offset, unit_duration_ms, seq)
    else
      {[], seq}
    end
  end

  defp generate_follows(
         follows_per_time_unit,
         user_id,
         num_users,
         unit_offset,
         unit_duration_ms,
         seq
       ) do
    count = trunc(follows_per_time_unit)
    fractional = follows_per_time_unit - count

    {base_events, seq} =
      Enum.reduce(1..count, {[], seq}, fn _idx, {events_acc, seq_acc} ->
        {new_event, next_seq} =
          build_follow_event(user_id, num_users, unit_offset, unit_duration_ms, seq_acc)

        {new_event ++ events_acc, next_seq}
      end)

    if fractional > 0 and :rand.uniform() < fractional do
      {extra_events, next_seq} =
        build_follow_event(user_id, num_users, unit_offset, unit_duration_ms, seq)

      {base_events ++ extra_events, next_seq}
    else
      {base_events, seq}
    end
  end

  defp build_follow_event(user_id, num_users, unit_offset, unit_duration_ms, seq) do
    case random_subject_id(user_id, num_users) do
      nil ->
        {[], seq}

      subject_id ->
        offset = unit_offset + :rand.uniform(unit_duration_ms) - 1
        next_seq = seq + 1

        {[{offset, seq, user_id, subject_id}], next_seq}
    end
  end

  defp random_subject_id(_user_id, 1), do: nil

  defp random_subject_id(user_id, num_users) do
    subject_id = :rand.uniform(num_users)

    if subject_id == user_id do
      random_subject_id(user_id, num_users)
    else
      subject_id
    end
  end

  defp lookup_tier(user_id, num_users, tiers, follower_density) do
    follower_count = FollowerGraph.follower_count(user_id, num_users, follower_density)

    Enum.find(tiers, List.last(tiers), fn tier ->
      follower_count <= tier.max_followers
    end)
  end

  defp follow_from_tuple({offset_ms, _seq, actor_id, subject_id}) do
    %{offset_ms: offset_ms, actor_id: actor_id, subject_id: subject_id}
  end
end
