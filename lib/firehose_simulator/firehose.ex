defmodule FirehoseSimulator.Firehose do
  alias Phoenix.PubSub
  alias FirehoseSimulator.Event

  use GenServer

  @timer_ms 1000

  def status() do
    GenServer.call(__MODULE__, :status)
  end

  def add_event(attrs) when is_map(attrs) do
    GenServer.call(__MODULE__, {:add_event, attrs})
  end

  def reset() do
    GenServer.call(__MODULE__, :reset)
  end

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    schedule_event()
    {:ok, default_state()}
  end

  def handle_call(:status, _from, state) do
    {:reply, state, state}
  end

  def handle_call(:reset, _from, _state) do
    state = default_state()
    {:reply, :ok, state}
  end

  def handle_call({:add_event, attrs}, _from, state) do
    next_state = update_in(state.events, &(&1 ++ [attrs]))
    {:reply, {:ok, attrs}, next_state}
  end

  def handle_info(:event, state) do
    schedule_event()

    if state.events == [] do
      {:noreply, state}
    else
      updated_events =
        Enum.map(state.events, fn event ->
          event
          |> Event.from_config()
          |> publish_event()

          Map.update!(event, "emitted_count", &(&1 + 1))
        end)

      now = DateTime.utc_now() |> DateTime.to_iso8601()

      {:noreply,
       %{
         state
         | events: updated_events,
           events_count: state.events_count + length(state.events),
           last_event_at: now
       }}
    end
  end

  defp schedule_event() do
    Process.send_after(self(), :event, @timer_ms)
  end

  defp publish_event(event) do
    PubSub.broadcast(FirehoseSimulator.PubSub, "firehose", event)
  end

  defp default_state() do
    %{events_count: 0, last_event_at: nil, events: []}
  end
end
