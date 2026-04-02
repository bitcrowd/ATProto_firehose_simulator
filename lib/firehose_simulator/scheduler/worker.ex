defmodule FirehoseSimulator.Scheduler.Worker do
  @moduledoc """
  Scheduler worker that owns a partition of sessions.

  Runs a continuous loop that:
  1. Scans its ETS partition for sessions due for a get_timeline request
  2. Executes get_timeline in parallel via Task.async_stream
  3. Removes expired sessions

  ## Parallelism

  Since get_timeline is a DB call (I/O bound), each worker spawns tasks to
  parallelize the queries. The `max_concurrency` is bounded by the DB pool
  size divided by the number of workers, so we don't exhaust connections.
  """
  use GenServer

  require Logger

  alias FirehoseSimulator.Data
  alias FirehoseSimulator.Store

  @doc "Get the registered name for a partition."
  def via(partition), do: :"feed_sim_worker_#{partition}"

  def start_link(opts) do
    partition = Keyword.fetch!(opts, :partition)
    GenServer.start_link(__MODULE__, opts, name: via(partition))
  end

  @impl true
  def init(opts) do
    partition = Keyword.fetch!(opts, :partition)
    num_partitions = Keyword.fetch!(opts, :num_partitions)
    configured_max_concurrency = Keyword.get(opts, :max_concurrency)

    max_concurrency =
      if is_integer(configured_max_concurrency) and configured_max_concurrency > 0 do
        configured_max_concurrency
      else
        pool_size = Application.get_env(:firehose_simulator, :scheduler_db_pool_size, 50)
        max(div(pool_size, num_partitions), 1)
      end

    table = Store.table_name(partition)

    state = %{
      partition: partition,
      num_partitions: num_partitions,
      table: table,
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

    sessions =
      if :ets.whereis(table) == :undefined do
        []
      else
        :ets.tab2list(table)
      end

    session_count = length(sessions)
    done_counter = :counters.new(1, [:atomics])

    query_results =
      sessions
      |> Stream.flat_map(fn {id, session} ->
        cond do
          now >= session.expires_at ->
            Store.complete(id, state.num_partitions)
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
              case AppView.get_timeline(did, 20) do
                %{"feed" => feed} when is_list(feed) ->
                  feed

                body when is_binary(body) ->
                  case Jason.decode(body) do
                    {:ok, %{"feed" => feed}} when is_list(feed) ->
                      feed

                    _ ->
                      Logger.warning(
                        "[Worker #{state.partition}] unexpected AppView timeline response: #{inspect(body)}"
                      )

                      []
                  end

                {:error, reason} ->
                  throw({:error, reason})

                other ->
                  Logger.warning(
                    "[Worker #{state.partition}] unexpected AppView timeline response: #{inspect(other)}"
                  )

                  []
              end

            latency = System.monotonic_time(:millisecond) - t0

            :telemetry.execute(
              [:firehose_simulator, :worker, :query],
              %{latency_ms: latency, rows: length(results)},
              %{status: :ok}
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
                %{status: :exit, reason: inspect(reason)}
              )

              {:error, {:exit, reason}}

            kind, reason ->
              latency = System.monotonic_time(:millisecond) - t0

              :telemetry.execute(
                [:firehose_simulator, :worker, :query],
                %{latency_ms: latency, rows: 0},
                %{status: :error, reason: inspect(reason)}
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
            %{status: :timeout}
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
        %{partition: state.partition}
      )
    end

    had_work = queries_dispatched > 0 or done_count > 0
    {had_work, query_results}
  end
end
