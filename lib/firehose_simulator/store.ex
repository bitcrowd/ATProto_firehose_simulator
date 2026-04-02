defmodule FirehoseSimulator.Store do
  @moduledoc """
  ETS-backed per-player session store.
  """
  use GenServer

  @type partition_tables :: %{optional(non_neg_integer()) => :ets.tid()}

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, :ok, name: name)
  end

  @spec ensure_partition_tables(GenServer.server(), pos_integer()) :: :ok
  def ensure_partition_tables(store, num_partitions)
      when is_integer(num_partitions) and num_partitions > 0 do
    GenServer.call(store, {:ensure_partition_tables, num_partitions})
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

  @impl true
  def init(:ok) do
    completed_table =
      :ets.new(:completed_sessions, [
        :set,
        :public,
        write_concurrency: true
      ])

    :ets.insert(completed_table, {:count, 0})

    {:ok, %{completed_table: completed_table, partition_tables: %{}}}
  end

  @impl true
  def handle_call({:ensure_partition_tables, num_partitions}, _from, state) do
    partition_tables =
      Enum.reduce(0..(num_partitions - 1), state.partition_tables, fn partition, acc ->
        Map.put_new_lazy(acc, partition, fn ->
          :ets.new(:sessions, [
            :set,
            :public,
            read_concurrency: true,
            write_concurrency: true
          ])
        end)
      end)

    {:reply, :ok, %{state | partition_tables: partition_tables}}
  end

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
        acc + :ets.info(table, :size)
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
end
