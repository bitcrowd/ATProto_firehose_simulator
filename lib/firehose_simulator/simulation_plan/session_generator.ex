defmodule FirehoseSimulator.SimulationPlan.SessionGenerator do
  @moduledoc """
  Generates a deterministic in-memory session plan from a follower graph configuration.

  Each user gets one session per simulated time unit, starting at a random offset
  that guarantees the session fits within the unit.

  The same inputs + seed always produce byte-identical output.

  ## Example

      FirehoseSimulator.SimulationPlan.SessionGenerator.generate(%Sessions{...})
  """

  alias FirehoseSimulator.FollowerGraph
  alias FirehoseSimulator.SimulationPlan.Sessions

  @default_unit_duration_ms 86_400_000

  @type session :: %{
          offset_ms: non_neg_integer(),
          user_id: pos_integer(),
          duration_ms: pos_integer()
        }

  @type t :: %__MODULE__{
          sessions: [session()]
        }

  defstruct sessions: []

  @doc """
  Generate an in-memory session plan from a `%Sessions{}` config.
  """
  def generate(%Sessions{} = config) do
    :rand.seed(:exsss, {config.seed, config.seed, config.seed})

    sessions =
      build_sessions(
        config.max_active_user_id,
        config.n,
        config.time_units,
        config.tiers,
        @default_unit_duration_ms
      )

    sessions = Enum.sort_by(sessions, &elem(&1, 0))
    sessions = Enum.map(sessions, &session_from_tuple/1)

    %__MODULE__{sessions: sessions}
  end

  defp build_sessions(max_active_user_id, n, time_units, tiers, unit_duration_ms) do
    for unit <- 0..(time_units - 1), user_id <- 1..max_active_user_id do
      unit_offset = unit * unit_duration_ms
      tier = lookup_tier(user_id, n, tiers)

      session_ms = tier.session_minutes * 60_000
      max_start = max(unit_duration_ms - session_ms, 1)
      start_offset = unit_offset + :rand.uniform(max_start) - 1

      {start_offset, user_id, session_ms}
    end
  end

  @doc """
  Look up the tier for a user based on their follower count.

  Tiers must be sorted ascending by `:max_followers`. First match wins.
  """
  def lookup_tier(user_id, n, tiers) do
    follower_count = FollowerGraph.follower_count(user_id, n)

    Enum.find(tiers, List.last(tiers), fn tier ->
      follower_count <= tier.max_followers
    end)
  end

  @doc """
  Write a generated session plan to CSV.
  """
  def write_to_csv(%__MODULE__{} = plan, path) when is_binary(path) do
    {:ok, file} = File.open(path, [:write, :utf8])
    IO.write(file, "offset_ms,user_id,duration_ms\n")

    Enum.each(plan.sessions, fn session ->
      IO.write(file, "#{session.offset_ms},#{session.user_id},#{session.duration_ms}\n")
    end)

    File.close(file)
    :ok
  end

  @doc """
  Load a session plan from CSV.
  """
  def load_from_csv(path) when is_binary(path) do
    with {:ok, csv} <- File.read(path),
         {:ok, sessions} <- parse_csv(csv) do
      {:ok, %__MODULE__{sessions: sessions}}
    else
      {:error, :enoent} -> {:error, "cannot read sessions csv at #{path}"}
      {:error, _reason} = error -> error
    end
  end

  @doc """
  Load a session plan from CSV, raising on failure.
  """
  def load_from_csv!(path) when is_binary(path) do
    case load_from_csv(path) do
      {:ok, plan} -> plan
      {:error, message} -> raise RuntimeError, message
    end
  end

  defp session_from_tuple({offset_ms, user_id, duration_ms}) do
    %{offset_ms: offset_ms, user_id: user_id, duration_ms: duration_ms}
  end

  defp parse_csv(csv) do
    case String.split(csv, "\n", trim: true) do
      ["offset_ms,user_id,duration_ms" | rows] ->
        rows
        |> Enum.map(&String.split(&1, ",", parts: 3))
        |> Enum.reduce_while({:ok, []}, fn
          [offset_ms, user_id, duration_ms], {:ok, acc} ->
            with {offset_ms, ""} <- Integer.parse(offset_ms),
                 {user_id, ""} <- Integer.parse(user_id),
                 {duration_ms, ""} <- Integer.parse(duration_ms) do
              {:cont,
               {:ok, acc ++ [%{offset_ms: offset_ms, user_id: user_id, duration_ms: duration_ms}]}}
            else
              _ -> {:halt, {:error, "invalid sessions csv"}}
            end

          _row, _acc ->
            {:halt, {:error, "invalid sessions csv"}}
        end)

      _ ->
        {:error, "invalid sessions csv"}
    end
  end
end
