defmodule FirehoseSimulator.Store do
  @moduledoc """
  ETS-backed session store.

  Sessions are stored across N partition tables (`sessions_0`, `sessions_1`, …)
  so each worker reads only its own table — no full-table scans.

  Partition tables are created lazily by `bulk_insert/2`.
  """
  use GenServer

  @completed_table :completed_sessions

  # --- Client API ---

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Insert a batch of sessions, partitioned across N tables.
  Creates the partition tables if they don't exist.
  """
  def bulk_insert(sessions, num_partitions) do
    ensure_partition_tables(num_partitions)

    Enum.each(sessions, fn session ->
      partition = rem(:erlang.phash2(session.id), num_partitions)
      :ets.insert(table_name(partition), {session.id, session})
    end)

    :ok
  end

  @doc """
  Get all sessions for a given partition.
  Returns a list of {id, session_map} tuples.
  """
  def get_partition(partition, _num_partitions) do
    :ets.tab2list(table_name(partition))
  end

  @doc """
  Update a session in place.
  """
  def update(id, session, num_partitions) do
    partition = rem(:erlang.phash2(id), num_partitions)
    :ets.insert(table_name(partition), {id, session})
  end

  @doc """
  Remove a completed session and track it.
  """
  def complete(id, num_partitions) do
    partition = rem(:erlang.phash2(id), num_partitions)
    :ets.delete(table_name(partition), id)
    :ets.update_counter(@completed_table, :count, {2, 1}, {:count, 0})
  end

  @doc """
  Clear all sessions (for resetting between runs).
  """
  def clear do
    for table <- :ets.all(),
        is_atom(table),
        table |> Atom.to_string() |> String.starts_with?("sessions_") do
      try do
        :ets.delete_all_objects(table)
      catch
        :error, :badarg -> :ok
      end
    end

    :ets.insert(@completed_table, {:count, 0})
    :ok
  end

  @doc "Count of active (in-progress) sessions."
  def count_active do
    for table <- :ets.all(),
        is_atom(table),
        table |> Atom.to_string() |> String.starts_with?("sessions_"),
        reduce: 0 do
      acc -> acc + :ets.info(table, :size)
    end
  end

  @doc "Count of total sessions (active + completed)."
  def count_total do
    count_active() + count_completed()
  end

  @doc "Count of completed sessions."
  def count_completed do
    case :ets.lookup(@completed_table, :count) do
      [{:count, n}] -> n
      [] -> 0
    end
  end

  # --- Internal ---

  def table_name(partition), do: :"sessions_#{partition}"

  @doc false
  def ensure_partition_tables(num_partitions) do
    for partition <- 0..(num_partitions - 1) do
      name = table_name(partition)

      if :ets.whereis(name) == :undefined do
        :ets.new(name, [
          :set,
          :public,
          :named_table,
          read_concurrency: true,
          write_concurrency: true
        ])
      end
    end
  end

  # --- Server ---

  @impl true
  def init(_) do
    :ets.new(@completed_table, [
      :set,
      :public,
      :named_table,
      write_concurrency: true
    ])

    :ets.insert(@completed_table, {:count, 0})

    {:ok, %{}}
  end
end
