defmodule FirehoseSimulator.SimulationPlan.FollowsGenerator do
  @moduledoc """
  Generates a deterministic in-memory follows plan from a follower graph configuration.

  Follow events are distributed at random offsets throughout each simulated time unit,
  independent of session schedules. Uses its own RNG seed so changing
  follow config does not affect session generation.

  ## Example

      FirehoseSimulator.SimulationPlan.FollowsGenerator.generate(%Follows{...})
  """

  alias FirehoseSimulator.FollowerGraph
  alias FirehoseSimulator.SimulationPlan.Follows

  @default_unit_duration_ms 86_400_000

  @type follow :: %{
          offset_ms: non_neg_integer(),
          actor_id: pos_integer(),
          subject_id: pos_integer()
        }

  @type t :: %__MODULE__{
          follows: [follow()]
        }

  defstruct follows: []

  @doc """
  Generate an in-memory follows plan from a `%Follows{}` config.
  """
  def generate(%Follows{} = config) do
    :rand.seed(:exsss, {config.seed, config.seed, config.seed})

    follows =
      build_follows(
        config.max_active_user_id,
        config.n,
        config.time_units,
        config.tiers,
        @default_unit_duration_ms
      )

    follows = Enum.sort_by(follows, fn {offset, seq, _actor, _subject} -> {offset, seq} end)
    follows = Enum.map(follows, &follow_from_tuple/1)

    %__MODULE__{follows: follows}
  end

  defp build_follows(max_active_user_id, n, time_units, tiers, unit_duration_ms) do
    {events, _next_seq} =
      for unit <- 0..(time_units - 1), user_id <- 1..max_active_user_id, reduce: {[], 0} do
        {acc_events, seq} ->
          unit_offset = unit * unit_duration_ms
          tier = lookup_tier(user_id, n, tiers)

          {new_events, next_seq} =
            generate_follows(
              tier.follows_per_day,
              user_id,
              n,
              unit_offset,
              unit_duration_ms,
              seq
            )

          {new_events ++ acc_events, next_seq}
      end

    events
  end

  defp generate_follows(follows_per_day, user_id, n, unit_offset, unit_duration_ms, seq)
       when follows_per_day < 1.0 do
    if :rand.uniform() < follows_per_day do
      build_follow_event(user_id, n, unit_offset, unit_duration_ms, seq)
    else
      {[], seq}
    end
  end

  defp generate_follows(follows_per_day, user_id, n, unit_offset, unit_duration_ms, seq) do
    count = trunc(follows_per_day)
    fractional = follows_per_day - count

    {base_events, seq} =
      Enum.reduce(1..count, {[], seq}, fn _idx, {events_acc, seq_acc} ->
        {new_event, next_seq} =
          build_follow_event(user_id, n, unit_offset, unit_duration_ms, seq_acc)

        {new_event ++ events_acc, next_seq}
      end)

    if fractional > 0 and :rand.uniform() < fractional do
      {extra_events, next_seq} =
        build_follow_event(user_id, n, unit_offset, unit_duration_ms, seq)

      {base_events ++ extra_events, next_seq}
    else
      {base_events, seq}
    end
  end

  defp build_follow_event(user_id, n, unit_offset, unit_duration_ms, seq) do
    case random_subject_id(user_id, n) do
      nil ->
        {[], seq}

      subject_id ->
        offset = unit_offset + :rand.uniform(unit_duration_ms) - 1
        next_seq = seq + 1

        {[{offset, seq, user_id, subject_id}], next_seq}
    end
  end

  defp random_subject_id(_user_id, 1), do: nil

  defp random_subject_id(user_id, n) do
    subject_id = :rand.uniform(n)

    if subject_id == user_id do
      random_subject_id(user_id, n)
    else
      subject_id
    end
  end

  defp lookup_tier(user_id, n, tiers) do
    follower_count = FollowerGraph.follower_count(user_id, n)

    Enum.find(tiers, List.last(tiers), fn tier ->
      follower_count <= tier.max_followers
    end)
  end

  @doc """
  Write a generated follows plan to CSV.
  """
  def write_to_csv(%__MODULE__{} = plan, path) when is_binary(path) do
    {:ok, file} = File.open(path, [:write, :utf8])
    IO.write(file, "offset_ms,actor_id,subject_id\n")

    Enum.each(plan.follows, fn follow ->
      IO.write(file, "#{follow.offset_ms},#{follow.actor_id},#{follow.subject_id}\n")
    end)

    File.close(file)
    :ok
  end

  @doc """
  Load a follows plan from CSV.
  """
  def load_from_csv(path) when is_binary(path) do
    with {:ok, csv} <- File.read(path),
         {:ok, follows} <- parse_csv(csv) do
      {:ok, %__MODULE__{follows: follows}}
    else
      {:error, :enoent} -> {:error, "cannot read follows csv at #{path}"}
      {:error, _reason} = error -> error
    end
  end

  @doc """
  Load a follows plan from CSV, raising on failure.
  """
  def load_from_csv!(path) when is_binary(path) do
    case load_from_csv(path) do
      {:ok, plan} -> plan
      {:error, message} -> raise RuntimeError, message
    end
  end

  defp follow_from_tuple({offset_ms, _seq, actor_id, subject_id}) do
    %{offset_ms: offset_ms, actor_id: actor_id, subject_id: subject_id}
  end

  defp parse_csv(csv) do
    case String.split(csv, "\n", trim: true) do
      ["offset_ms,actor_id,subject_id" | rows] ->
        rows
        |> Enum.map(&String.split(&1, ",", parts: 3))
        |> Enum.reduce_while({:ok, []}, fn
          [offset_ms, actor_id, subject_id], {:ok, acc} ->
            with {offset_ms, ""} <- Integer.parse(offset_ms),
                 {actor_id, ""} <- Integer.parse(actor_id),
                 {subject_id, ""} <- Integer.parse(subject_id) do
              {:cont,
               {:ok,
                acc ++
                  [%{offset_ms: offset_ms, actor_id: actor_id, subject_id: subject_id}]}}
            else
              _ -> {:halt, {:error, "invalid follows csv"}}
            end

          _row, _acc ->
            {:halt, {:error, "invalid follows csv"}}
        end)

      _ ->
        {:error, "invalid follows csv"}
    end
  end
end
