defmodule FirehoseSimulator.Player.Scheduler.Worker do
  @moduledoc """
  Scheduler worker that owns a partition of sessions.
  """
  use GenServer

  require Logger

  alias FirehoseSimulator.Data
  alias FirehoseSimulator.Player.Store

  def start_link(opts) do
    {name, opts} = Keyword.pop!(opts, :name)

    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def start_processing(worker) do
    GenServer.call(worker, :start_processing, :infinity)
  end

  def pause_processing(worker) do
    GenServer.call(worker, :pause_processing, :infinity)
  end

  @impl true
  def init(opts) do
    player_id = Keyword.fetch!(opts, :player_id)
    store = Keyword.fetch!(opts, :store)
    partition = Keyword.fetch!(opts, :partition)
    num_partitions = Keyword.fetch!(opts, :num_partitions)
    timeline_limit = Keyword.fetch!(opts, :timeline_limit)
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
      max_concurrency: max_concurrency,
      batch_size: max_concurrency,
      timeline_limit: timeline_limit,
      lifecycle_state: :loaded
    }

    Logger.info("[Worker #{partition}] Started (max_concurrency=#{max_concurrency})")

    {:ok, state}
  end

  @impl true
  def handle_call(:start_processing, _from, %{lifecycle_state: :running} = state) do
    {:reply, :ok, state}
  end

  def handle_call(:start_processing, _from, state) do
    send(self(), :work)
    {:reply, :ok, %{state | lifecycle_state: :running}}
  end

  def handle_call(:pause_processing, _from, %{lifecycle_state: :running} = state) do
    {:reply, :ok, %{state | lifecycle_state: :paused}}
  end

  def handle_call(:pause_processing, _from, state) do
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:work, %{lifecycle_state: :running} = state) do
    {had_work, _results} = run_cycle(state)

    if had_work do
      send(self(), :work)
    else
      Process.send_after(self(), :work, 1)
    end

    {:noreply, state}
  end

  def handle_info(:work, state) do
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @doc false
  def run_cycle(state) do
    start_time = System.monotonic_time(:millisecond)
    now = start_time
    table = state.table

    expired_count = Store.expire_sessions(table, state.completed_table, now)
    session_count = Store.active_count(table)

    due_sessions =
      case Store.select_due(table, now, state.batch_size) do
        :"$end_of_table" -> []
        {sessions, _continuation} -> sessions
      end

    query_results =
      if due_sessions == [] do
        %{ok: 0, timeout: 0, error: 0}
      else
        due_sessions
        |> Task.async_stream(
          fn {_id, session} ->
            t0 = System.monotonic_time(:millisecond)
            lag_ms = max(now - session.next_request_at, 0)

            try do
              did = Data.did_for_user_id(session.user_id)

              results =
                case Dataplane.get_timeline(did, state.timeline_limit) do
                  %{"items" => items} when is_list(items) ->
                    items

                  {:error, error} ->
                    Logger.error("[Worker #{state.partition}] error: #{inspect(error)}")

                  other ->
                    Logger.warning(
                      "[Worker #{state.partition}] unexpected timeline response: #{inspect(other)}"
                    )

                    []
                end

              latency = System.monotonic_time(:millisecond) - t0

              :telemetry.execute(
                [:firehose_simulator, :worker, :query],
                %{latency_ms: latency, rows: length(results), lag_ms: lag_ms},
                %{status: :ok, player_id: state.player_id}
              )

              updated = %{session | next_request_at: now + session.request_interval_ms}
              Store.put_session(table, updated)
              {:ok, length(results)}
            catch
              :exit, reason ->
                latency = System.monotonic_time(:millisecond) - t0

                :telemetry.execute(
                  [:firehose_simulator, :worker, :query],
                  %{latency_ms: latency, rows: 0, lag_ms: lag_ms},
                  %{status: :exit, reason: inspect(reason), player_id: state.player_id}
                )

                {:error, {:exit, reason}}

              kind, reason ->
                latency = System.monotonic_time(:millisecond) - t0

                :telemetry.execute(
                  [:firehose_simulator, :worker, :query],
                  %{latency_ms: latency, rows: 0, lag_ms: lag_ms},
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
              %{latency_ms: 30_000, rows: 0, lag_ms: 0},
              %{status: :timeout, player_id: state.player_id}
            )

            %{acc | timeout: acc.timeout + 1}

          _, acc ->
            %{acc | error: acc.error + 1}
        end)
      end

    elapsed = System.monotonic_time(:millisecond) - start_time
    queries_dispatched = query_results.ok + query_results.error + query_results.timeout

    if queries_dispatched > 0 or expired_count > 0 do
      measurements = %{
        session_count: session_count,
        ok: query_results.ok,
        errors: query_results.error,
        completed: expired_count,
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

    had_work = queries_dispatched > 0 or expired_count > 0
    {had_work, query_results}
  end
end
