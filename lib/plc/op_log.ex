defmodule PLC.OpLog do
  use Agent

  def start_link(initial_value) do
    Agent.start_link(fn -> initial_value end, name: __MODULE__)
  end

  def get_ops(did), do: Agent.get(__MODULE__, &Map.get(&1, did, []))

  def last_op(did), do: get_ops(did) |> List.last()

  def put_op(did, op) do
    Agent.update(__MODULE__, fn ops ->
      Map.update(ops, did, [op], &append_op(&1, op))
    end)
  end

  defp append_op(ops, op), do: ops ++ [op]
end
