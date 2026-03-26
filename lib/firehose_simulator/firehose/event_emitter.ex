defmodule FirehoseSimulator.Firehose.EventEmitter do
  use GenServer

  alias FirehoseSimulator.Event
  alias Phoenix.PubSub

  def start_link(attrs) do
    GenServer.start_link(__MODULE__, attrs)
  end

  def status(pid) when is_pid(pid) do
    GenServer.call(pid, :status)
  end

  def topic(event_id), do: "firehose:#{event_id}"

  @impl true
  def init(%{event: %{"time_ms" => time_ms}} = attrs) do
    event =
      attrs.event
      |> Map.put_new("emitted_count", 0)
      |> Map.put_new("last_emitted_at", nil)

    schedule_emit(time_ms)
    {:ok, %{attrs | event: event}}
  end

  @impl true
  def handle_call(:status, _from, %{event: event} = state) do
    {:reply, event, state}
  end

  @impl true
  def handle_info(:emit_event, %{event: event} = state) do
    payload = Event.from_config(event)
    emitted_at = DateTime.utc_now() |> DateTime.to_iso8601()

    updated_event =
      event
      |> Map.update!("emitted_count", &(&1 + 1))
      |> Map.put("last_emitted_at", emitted_at)

    PubSub.broadcast(FirehoseSimulator.PubSub, "firehose", payload)

    PubSub.broadcast(
      FirehoseSimulator.PubSub,
      topic(event["id"]),
      {:firehose_event_updated, updated_event}
    )

    schedule_emit(updated_event["time_ms"])

    {:noreply, %{state | event: updated_event}}
  end

  defp schedule_emit(time_ms) do
    Process.send_after(self(), :emit_event, time_ms)
  end
end
