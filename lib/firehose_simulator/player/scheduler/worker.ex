defmodule FirehoseSimulator.Player.Scheduler.Worker do
  @moduledoc """
  Scheduler worker that owns a partition of sessions.

  Runs a continuous loop that:
  1. Scans its ETS partition for sessions due for a get_timeline request
  2. Executes get_timeline in parallel via Task.async_stream
  3. Removes expired sessions
  """
  use GenServer

  require Logger

  alias FirehoseSimulator.Data
  alias FirehoseSimulator.Player.Store

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    player_id = Keyword.fetch!(opts, :player_id)
    store = Keyword.fetch!(opts, :store)
    partition = Keyword.fetch!(opts, :partition)
    num_partitions = Keyword.fetch!(opts, :num_partitions)
    configured_max_concurrency = Keyword.get(opts, :max_concurrency)

    max_concurrency =
      if is_integer(configured_max_concurrency) and configured_max_concurrency > 0 do
        configured_max_concurrency
      else
        pool_size = 50
        max(div(pool_size, num_partitions), 1)
      end

    table = store |> Store.partition_tables() |> Map.fetch!(partition)
    completed_table = Store.completed_table(store)

    state = %{
      player_id: player_id,
      partition: partition,
      num_partitions: num_partitions,
      store: store,
      table: table,
      completed_table: completed_table,
      max_concurrency: max_concurrency
    }

    Logger.info("[Worker #{partition}] Started (max_concurrency=#{max_concurrency})")

    send(self(), :start_loop)

    {:ok, state}
  end

  @impl true
  def handle_info(:start_loop, state) do
    spawn_link(fn -> run_loop(state) end)

    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # --- Internal ---

  defp run_loop(state) do
    {had_work, _results} = run_cycle(state)

    unless had_work do
      Process.sleep(1)
    end

    run_loop(state)
  end

  @doc false
  def run_cycle(state) do
    start_time = System.monotonic_time(:millisecond)
    now = start_time

    table = state.table

    sessions = safe_tab2list(table)

    session_count = length(sessions)
    done_counter = :counters.new(1, [:atomics])

    query_results =
      sessions
      |> Stream.flat_map(fn {id, session} ->
        cond do
          now >= session.expires_at ->
            :ets.delete(table, id)
            :ets.update_counter(state.completed_table, :count, {2, 1}, {:count, 0})
            :counters.add(done_counter, 1, 1)
            []

          now >= session.next_request_at ->
            [{id, session}]

          true ->
            []
        end
      end)
      |> Task.async_stream(
        fn {id, session} ->
          t0 = System.monotonic_time(:millisecond)

          try do
            did = Data.did_for_user_id(session.user_id)

            results =
              case Dataplane.get_timeline(did, 20) do
                %{"items" => items} when is_list(items) ->
                  items

                {:error, reason} ->
                  throw({:error, reason})

                other ->
                  Logger.warning(
                    "[Worker #{state.partition}] unexpected timeline response: #{inspect(other)}"
                  )

                  []
              end

            latency = System.monotonic_time(:millisecond) - t0

            :telemetry.execute(
              [:firehose_simulator, :worker, :query],
              %{latency_ms: latency, rows: length(results)},
              %{status: :ok, player_id: state.player_id}
            )

            updated = %{session | next_request_at: now + session.request_interval_ms}
            :ets.insert(table, {id, updated})
            {:ok, length(results)}
          catch
            :exit, reason ->
              latency = System.monotonic_time(:millisecond) - t0

              :telemetry.execute(
                [:firehose_simulator, :worker, :query],
                %{latency_ms: latency, rows: 0},
                %{status: :exit, reason: inspect(reason), player_id: state.player_id}
              )

              {:error, {:exit, reason}}

            kind, reason ->
              latency = System.monotonic_time(:millisecond) - t0

              :telemetry.execute(
                [:firehose_simulator, :worker, :query],
                %{latency_ms: latency, rows: 0},
                %{status: :error, reason: inspect(reason), player_id: state.player_id}
              )

              {:error, {kind, reason}}
          end
        end,
        max_concurrency: state.max_concurrency,
        timeout: 30_000,
        on_timeout: :kill_task
      )
      |> Enum.reduce(%{ok: 0, timeout: 0, error: 0}, fn
        {:ok, {:ok, _rows}}, acc ->
          %{acc | ok: acc.ok + 1}

        {:ok, {:error, _}}, acc ->
          %{acc | error: acc.error + 1}

        {:exit, :timeout}, acc ->
          :telemetry.execute(
            [:firehose_simulator, :worker, :query],
            %{latency_ms: 30_000, rows: 0},
            %{status: :timeout, player_id: state.player_id}
          )

          %{acc | timeout: acc.timeout + 1}

        _, acc ->
          %{acc | error: acc.error + 1}
      end)

    done_count = :counters.get(done_counter, 1)
    elapsed = System.monotonic_time(:millisecond) - start_time
    queries_dispatched = query_results.ok + query_results.error + query_results.timeout

    if queries_dispatched > 0 or done_count > 0 do
      measurements = %{
        session_count: session_count,
        ok: query_results.ok,
        errors: query_results.error,
        completed: done_count,
        timeouts: query_results.timeout
      }

      measurements =
        if queries_dispatched > 0,
          do: Map.put(measurements, :duration_ms, elapsed),
          else: measurements

      :telemetry.execute(
        [:firehose_simulator, :worker, :cycle],
        measurements,
        %{partition: state.partition, player_id: state.player_id}
      )
    end

    had_work = queries_dispatched > 0 or done_count > 0
    {had_work, query_results}
  end

  defp safe_tab2list(table) do
    try do
      :ets.tab2list(table)
    catch
      :error, :badarg -> []
    end
  end
end
