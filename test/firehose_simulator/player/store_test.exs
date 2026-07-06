defmodule FirehoseSimulator.Player.StoreTest do
  use ExUnit.Case, async: false
  import FirehoseSimulator.SessionFixtures
  alias FirehoseSimulator.Player.Store

  test "selects due sessions and expires completed sessions" do
    store_name = {:via, Registry, {FirehoseSimulator.Player.Registry, {"store-test", self()}}}
    store = start_supervised!({Store, [name: store_name, num_partitions: 2]})
    partition_tables = Store.partition_tables(store)
    completed_table = Store.completed_table(store)
    now = System.monotonic_time(:millisecond)

    due_session = session(1, now - 10, now + 1_000)
    future_session = session(2, now + 1_000, now + 2_000)
    expired_session = session(3, now - 50, now - 1)

    Store.put_session(Map.fetch!(partition_tables, rem(:erlang.phash2(1), 2)), due_session)
    Store.put_session(Map.fetch!(partition_tables, rem(:erlang.phash2(2), 2)), future_session)
    Store.put_session(Map.fetch!(partition_tables, rem(:erlang.phash2(3), 2)), expired_session)

    expired_count =
      partition_tables
      |> Map.values()
      |> Enum.map(&Store.expire_sessions(&1, completed_table, now))
      |> Enum.sum()

    due_ids =
      partition_tables
      |> Map.values()
      |> Enum.flat_map(fn table ->
        case Store.select_due(table, now, 10) do
          :"$end_of_table" -> []
          {sessions, _continuation} -> Enum.map(sessions, fn {id, _session} -> id end)
        end
      end)

    assert expired_count == 1
    assert due_ids == [1]
    assert Store.count_active(store) == 2
    assert Store.count_completed(store) == 1
    assert Store.count_total(store) == 3
  end

  test "keeps counts isolated per store" do
    store_one_name = {:via, Registry, {FirehoseSimulator.Player.Registry, {"store-one", self()}}}
    store_two_name = {:via, Registry, {FirehoseSimulator.Player.Registry, {"store-two", self()}}}

    store_one =
      start_supervised!(
        Supervisor.child_spec({Store, [name: store_one_name, num_partitions: 1]},
          id: {:store, :one}
        )
      )

    store_two =
      start_supervised!(
        Supervisor.child_spec({Store, [name: store_two_name, num_partitions: 1]},
          id: {:store, :two}
        )
      )

    now = System.monotonic_time(:millisecond)
    store_one_table = store_one |> Store.partition_tables() |> Map.fetch!(0)
    store_two_table = store_two |> Store.partition_tables() |> Map.fetch!(0)

    Store.put_session(store_one_table, session(11, now - 10, now + 100))
    Store.put_session(store_two_table, session(22, now + 10, now + 100))

    assert Store.count_active(store_one) == 1
    assert Store.count_active(store_two) == 1

    Store.expire_sessions(store_one_table, Store.completed_table(store_one), now + 1_000)

    assert Store.count_completed(store_one) == 1
    assert Store.count_completed(store_two) == 0
    assert Store.count_active(store_one) == 0
    assert Store.count_active(store_two) == 1
  end
end
