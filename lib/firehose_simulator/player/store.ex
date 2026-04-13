defmodule FirehoseSimulator.Player.Store do
  @moduledoc """
  ETS-backed per-player session store.
  """
  use GenServer

  @type partition_tables :: %{optional(non_neg_integer()) => :ets.tid()}
  @type session_row :: {term(), integer(), integer(), map()}

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    {name, opts} = Keyword.pop!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec partition_tables(GenServer.server()) :: partition_tables()
  def partition_tables(store) do
    GenServer.call(store, :partition_tables)
  end

  @spec completed_table(GenServer.server()) :: :ets.tid()
  def completed_table(store) do
    GenServer.call(store, :completed_table)
  end

  @spec clear(GenServer.server()) :: :ok
  def clear(store) do
    GenServer.call(store, :clear)
  end

  @spec count_active(GenServer.server()) :: non_neg_integer()
  def count_active(store) do
    GenServer.call(store, :count_active)
  end

  @spec count_total(GenServer.server()) :: non_neg_integer()
  def count_total(store) do
    count_active(store) + count_completed(store)
  end

  @spec count_completed(GenServer.server()) :: non_neg_integer()
  def count_completed(store) do
    GenServer.call(store, :count_completed)
  end

  @spec put_session(:ets.tid(), map()) :: true
  def put_session(table, session) when is_map(session) do
    :ets.insert(table, session_row(session))
  end

  @spec expire_sessions(:ets.tid(), :ets.tid(), integer()) :: non_neg_integer()
  def expire_sessions(table, completed_table, now) do
    spec = [{{:_, :_, :"$1", :_}, [{:"=<", :"$1", now}], [true]}]
    deleted = :ets.select_delete(table, spec)

    if deleted > 0 do
      :ets.update_counter(completed_table, :count, {2, deleted}, {:count, 0})
    end

    deleted
  end

  @spec select_due(:ets.tid(), integer(), pos_integer()) ::
          {list({term(), map()}), term()} | :"$end_of_table"
  def select_due(table, now, limit) do
    spec = [{{:"$1", :"$2", :_, :"$3"}, [{:"=<", :"$2", now}], [{{:"$1", :"$3"}}]}]
    :ets.select(table, spec, limit)
  end

  @spec active_count(:ets.tid()) :: non_neg_integer()
  def active_count(table) do
    case :ets.info(table, :size) do
      size when is_integer(size) -> size
      _other -> 0
    end
  end

  @impl true
  def init(opts) do
    num_partitions = Keyword.fetch!(opts, :num_partitions)

    partition_tables =
      for i <- 0..(num_partitions - 1), into: %{} do
        {i,
         :ets.new(:sessions, [
           :set,
           :public,
           read_concurrency: true,
           write_concurrency: true
         ])}
      end

    completed_table =
      :ets.new(:completed_sessions, [
        :set,
        :public,
        write_concurrency: true
      ])

    :ets.insert(completed_table, {:count, 0})

    {:ok, %{completed_table: completed_table, partition_tables: partition_tables}}
  end

  @impl true
  def handle_call(:partition_tables, _from, state) do
    {:reply, state.partition_tables, state}
  end

  def handle_call(:completed_table, _from, state) do
    {:reply, state.completed_table, state}
  end

  def handle_call(:clear, _from, state) do
    Enum.each(state.partition_tables, fn {_partition, table} ->
      :ets.delete_all_objects(table)
    end)

    :ets.delete_all_objects(state.completed_table)
    :ets.insert(state.completed_table, {:count, 0})

    {:reply, :ok, state}
  end

  def handle_call(:count_active, _from, state) do
    total =
      Enum.reduce(state.partition_tables, 0, fn {_partition, table}, acc ->
        acc + active_count(table)
      end)

    {:reply, total, state}
  end

  def handle_call(:count_completed, _from, state) do
    count =
      case :ets.lookup(state.completed_table, :count) do
        [{:count, n}] -> n
        [] -> 0
      end

    {:reply, count, state}
  end

  defp session_row(session) do
    {session.id, session.next_request_at, session.expires_at, session}
  end
end
