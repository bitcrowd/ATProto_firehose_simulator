defmodule FirehoseSimulator.Firehose do
  alias Phoenix.PubSub
  alias FirehoseSimulator.Event

  use GenServer

  @timer_ms 1000
  @default_did "did:plc:p64spcpyzphswrueqd4gdh5y"

  def status() do
    GenServer.call(__MODULE__, :status)
  end

  def set_did(did) when is_binary(did) do
    GenServer.call(__MODULE__, {:set_did, did})
  end

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    schedule_event()
    {:ok, %{did: @default_did, events_count: 0, last_event_at: nil}}
  end

  def handle_call(:status, _from, state) do
    {:reply, state, state}
  end

  def handle_call({:set_did, did}, _from, state) do
    if String.starts_with?(did, "did:") do
      {:reply, :ok, %{state | did: did}}
    else
      {:reply, {:error, "DID must start with did:"}, state}
    end
  end

  def handle_info(:event, state) do
    Event.next(state.did)
    |> publish_event()

    schedule_event()

    now = DateTime.utc_now() |> DateTime.to_iso8601()
    {:noreply, %{state | events_count: state.events_count + 1, last_event_at: now}}
  end

  defp schedule_event() do
    Process.send_after(self(), :event, @timer_ms)
  end

  defp publish_event(event) do
    PubSub.broadcast(FirehoseSimulator.PubSub, "firehose", event)
  end
end
