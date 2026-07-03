defmodule FirehoseSimulator.Player.Scheduler.WorkerTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog
  import FirehoseSimulator.SessionFixtures
  alias FirehoseSimulator.Player.Scheduler.Worker
  alias FirehoseSimulator.Player.Store
  alias FirehoseSimulator.TestTimelinePlug

  setup do
    start_supervised!({Registry, keys: :unique, name: FirehoseSimulator.Player.Registry})
    original_url = Application.get_env(:firehose_simulator, :dataplane_url)
    on_exit(fn -> Application.put_env(:firehose_simulator, :dataplane_url, original_url) end)
    :ok
  end

  test "run_cycle queries due sessions, updates them, and emits telemetry" do
    agent = start_supervised!({Agent, fn -> [{:ok, %{"items" => [%{"id" => 1}]}}] end})
    port = open_port()
    start_supervised!({Bandit, plug: {TestTimelinePlug, agent: agent}, port: port})

    Application.put_env(:firehose_simulator, :dataplane_url, "http://127.0.0.1:#{port}")

    store_name = {:via, Registry, {FirehoseSimulator.Player.Registry, {"worker-test", self()}}}
    store = start_supervised!({Store, [name: store_name, num_partitions: 1]})
    table = store |> Store.partition_tables() |> Map.fetch!(0)
    completed_table = Store.completed_table(store)
    now = System.monotonic_time(:millisecond)

    session = session(1, now - 10, now + 5_000)
    Store.put_session(table, session)

    query_handler_id = "worker-query-#{System.unique_integer([:positive])}"
    cycle_handler_id = "worker-cycle-#{System.unique_integer([:positive])}"

    attach_handler(query_handler_id, [:firehose_simulator, :worker, :query])
    attach_handler(cycle_handler_id, [:firehose_simulator, :worker, :cycle])

    on_exit(fn ->
      :telemetry.detach(query_handler_id)
      :telemetry.detach(cycle_handler_id)
    end)

    state = %{
      player_id: "player-test",
      partition: 0,
      num_partitions: 1,
      store: store,
      table: table,
      completed_table: completed_table,
      max_concurrency: 1,
      batch_size: 1,
      timeline_limit: 20
    }

    {had_work, results} = Worker.run_cycle(state)

    assert had_work
    assert results == %{ok: 1, timeout: 0, error: 0}

    assert_receive {:telemetry_event, [:firehose_simulator, :worker, :query], measurements,
                    metadata}

    assert measurements.rows == 1
    assert measurements.lag_ms >= 10
    assert metadata.status == :ok
    assert metadata.player_id == "player-test"

    assert_receive {:telemetry_event, [:firehose_simulator, :worker, :cycle], cycle_measurements,
                    cycle_metadata}

    assert cycle_measurements.ok == 1
    assert cycle_measurements.completed == 0
    assert cycle_measurements.session_count == 1
    assert cycle_metadata.partition == 0
    assert cycle_metadata.player_id == "player-test"

    [{1, next_request_at, expires_at, updated_session}] = :ets.lookup(table, 1)
    assert next_request_at > session.next_request_at
    assert expires_at == session.expires_at
    assert updated_session.next_request_at == next_request_at
  end

  test "run_cycle reports query errors when dataplane is unavailable" do
    unavailable_port = open_port()

    Application.put_env(
      :firehose_simulator,
      :dataplane_url,
      "http://127.0.0.1:#{unavailable_port}"
    )

    store_name =
      {:via, Registry, {FirehoseSimulator.Player.Registry, {"worker-error-test", self()}}}

    store = start_supervised!({Store, [name: store_name, num_partitions: 1]})
    table = store |> Store.partition_tables() |> Map.fetch!(0)
    completed_table = Store.completed_table(store)
    now = System.monotonic_time(:millisecond)

    session = session(2, now - 10, now + 5_000)
    Store.put_session(table, session)

    query_handler_id = "worker-query-error-#{System.unique_integer([:positive])}"
    attach_handler(query_handler_id, [:firehose_simulator, :worker, :query])
    on_exit(fn -> :telemetry.detach(query_handler_id) end)

    state = %{
      player_id: "player-error",
      partition: 0,
      num_partitions: 1,
      store: store,
      table: table,
      completed_table: completed_table,
      max_concurrency: 1,
      batch_size: 1,
      timeline_limit: 20
    }

    capture_log(fn ->
      {had_work, results} = Worker.run_cycle(state)

      assert had_work
      assert results == %{ok: 0, timeout: 0, error: 1}

      assert_receive {:telemetry_event, [:firehose_simulator, :worker, :query], measurements,
                      metadata}

      assert measurements.rows == 0
      assert measurements.lag_ms >= 10
      assert metadata.status == :error
      assert metadata.player_id == "player-error"
      assert [{2, _, _, _session}] = :ets.lookup(table, 2)
    end)
  end

  defp attach_handler(handler_id, event_name) do
    :telemetry.attach(
      handler_id,
      event_name,
      fn event, measurements, metadata, pid ->
        send(pid, {:telemetry_event, event, measurements, metadata})
      end,
      self()
    )
  end

  defp open_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(socket)
    :ok = :gen_tcp.close(socket)
    port
  end
end
