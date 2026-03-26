defmodule FirehoseSimulator.Firehose do
  alias FirehoseSimulator.Firehose.EventEmitter
  alias FirehoseSimulator.Firehose.EventSupervisor

  def add_event(attrs) when is_map(attrs) do
    event =
      attrs
      |> Map.put_new("emitted_count", 0)
      |> Map.put_new("last_emitted_at", nil)

    case EventSupervisor.start_child(%{event: event}) do
      {:ok, _pid} -> {:ok, event}
      {:error, {:already_started, pid}} -> {:ok, EventEmitter.status(pid)}
      {:error, reason} -> {:error, reason}
    end
  end

  def events() do
    EventSupervisor.children()
    |> Enum.map(&EventEmitter.status/1)
    |> Enum.sort_by(& &1["id"])
  end

  def reset() do
    EventSupervisor.children()
    |> Enum.each(fn pid ->
      :ok = EventSupervisor.terminate_child(pid)
    end)

    :ok
  end
end
