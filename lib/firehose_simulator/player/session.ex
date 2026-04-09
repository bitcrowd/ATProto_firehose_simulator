defmodule FirehoseSimulator.Player.Session do
  @moduledoc """
  Defines the data stored per session in ETS.

  Each session is stored as a tuple `{id, session}` in the :sessions ETS table.
  We use a plain map (not a struct) for ETS storage efficiency, but this module
  provides constructors and helpers.

  Sessions use wallclock timestamps (monotonic ms) for scheduling:
  - `next_request_at` — when the next get_timeline call is due
  - `expires_at` — when the session ends
  """

  @type t :: %{
          id: pos_integer(),
          user_id: pos_integer(),
          duration_ms: pos_integer(),
          request_interval_ms: pos_integer(),
          next_request_at: integer(),
          expires_at: integer(),
          started_at: integer()
        }

  @doc """
  Create a new session map.

  Options:
    - `:id` (required)
    - `:duration_ms` (required) — session lifetime in milliseconds
    - `:request_interval_ms` (required) — ms between get_timeline calls
    - `:user_id` — defaults to id
  """
  def new(opts) do
    id = Keyword.fetch!(opts, :id)
    duration_ms = Keyword.fetch!(opts, :duration_ms)
    interval = Keyword.fetch!(opts, :request_interval_ms)
    now = System.monotonic_time(:millisecond)

    %{
      id: id,
      user_id: Keyword.get(opts, :user_id, id),
      duration_ms: duration_ms,
      request_interval_ms: interval,
      next_request_at: now + rem(id, interval),
      expires_at: now + duration_ms,
      started_at: now
    }
  end

  @doc """
  Returns true if the session has expired.
  """
  def expired?(session, now \\ System.monotonic_time(:millisecond)) do
    now >= session.expires_at
  end

  @doc """
  Returns true if the session is due for a get_timeline request.
  """
  def due?(session, now \\ System.monotonic_time(:millisecond)) do
    now >= session.next_request_at
  end

  @doc """
  Advance `next_request_at` after a successful request.
  """
  def schedule_next(session, now \\ System.monotonic_time(:millisecond)) do
    %{session | next_request_at: now + session.request_interval_ms}
  end
end
