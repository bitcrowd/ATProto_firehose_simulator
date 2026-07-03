defmodule FirehoseSimulator.Scenario.Sessions do
  @moduledoc """
  Generates a deterministic in-memory session plan from a follower graph configuration.

  Each user gets one session per simulated time unit, starting at a random offset
  that guarantees the session fits within the unit.

  The same inputs + seed always produce byte-identical output.

  ## Example

      FirehoseSimulator.Scenario.Sessions.generate(%SessionsParams{...})
  """

  alias FirehoseSimulator.Scenario.Params.SessionsParams
  alias FirehoseSimulator.Scenario.Params.Tiers

  @default_unit_duration_ms 86_400_000

  @type session :: %{
          offset_ms: non_neg_integer(),
          user_id: pos_integer(),
          duration_ms: pos_integer()
        }

  @type t :: [session()]

  @doc """
  Generate an in-memory session plan from a `%SessionsParams{}` config.
  """
  def generate(
        %SessionsParams{} = config,
        seed,
        time_units,
        unit_duration_ms \\ @default_unit_duration_ms
      )
      when is_integer(seed) and is_integer(time_units) and time_units > 0 and
             is_integer(unit_duration_ms) and unit_duration_ms > 0 do
    :rand.seed(:exsss, {seed, seed, seed})

    sessions =
      build_sessions(
        config.max_active_user_id,
        config.num_users,
        config.follower_density,
        time_units,
        config.tiers,
        unit_duration_ms
      )

    sessions = Enum.sort_by(sessions, &elem(&1, 0))
    Enum.map(sessions, &session_from_tuple/1)
  end

  defp build_sessions(
         max_active_user_id,
         num_users,
         follower_density,
         time_units,
         tiers,
         unit_duration_ms
       ) do
    for unit <- 0..(time_units - 1), user_id <- 1..max_active_user_id do
      unit_offset = unit * unit_duration_ms
      tier = Tiers.lookup(user_id, num_users, tiers, follower_density)

      session_ms = tier.session_minutes * 60_000
      max_start = max(unit_duration_ms - session_ms, 1)
      start_offset = unit_offset + :rand.uniform(max_start) - 1

      {start_offset, user_id, session_ms}
    end
  end

  defp session_from_tuple({offset_ms, user_id, duration_ms}) do
    %{offset_ms: offset_ms, user_id: user_id, duration_ms: duration_ms}
  end
end
