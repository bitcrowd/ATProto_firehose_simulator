defmodule PLC.OpLog do
  @moduledoc false
  use Agent

  def start_link(initial_value) do
    Agent.start_link(fn -> initial_value end, name: __MODULE__)
  end

  def get_ops(did), do: Agent.get(__MODULE__, &Map.get(&1, did, [])) |> Enum.reverse()

  def last_op(did), do: Agent.get(__MODULE__, &Map.get(&1, did, [])) |> List.first()

  def put_op(did, op) do
    Agent.update(__MODULE__, fn ops ->
      Map.update(ops, did, [op], &[op | &1])
    end)
  end
end
