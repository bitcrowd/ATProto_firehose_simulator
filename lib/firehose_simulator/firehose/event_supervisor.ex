defmodule FirehoseSimulator.Firehose.EventSupervisor do
  use DynamicSupervisor

  alias FirehoseSimulator.Firehose.EventEmitter

  def start_link(arg) do
    DynamicSupervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def start_child(attrs) do
    DynamicSupervisor.start_child(__MODULE__, {EventEmitter, attrs})
  end

  def terminate_child(pid) do
    DynamicSupervisor.terminate_child(__MODULE__, pid)
  end

  def children() do
    __MODULE__
    |> DynamicSupervisor.which_children()
    |> Enum.map(fn {_id, pid, _type, _modules} -> pid end)
    |> Enum.filter(&is_pid/1)
  end

  @impl true
  def init(_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
