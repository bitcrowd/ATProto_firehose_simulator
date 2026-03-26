defmodule FirehoseSimulator.Firehose do
  use GenServer

  alias FirehoseSimulator.Firehose.EventEmitter
  alias FirehoseSimulator.Firehose.EventSupervisor

  def add_event(attrs) when is_map(attrs) do
    GenServer.call(__MODULE__, {:add_event, attrs})
  end

  def events() do
    EventSupervisor.children()
    |> Enum.map(&EventEmitter.status/1)
    |> Enum.sort_by(& &1["id"])
  end

  def remove_event(event_id) when is_integer(event_id) do
    GenServer.call(__MODULE__, {:remove_event, event_id})
  end

  def reset() do
    GenServer.call(__MODULE__, :reset)
  end

  def start_link(arg) do
    GenServer.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    {:ok, %{event_pids: %{}}}
  end

  @impl true
  def handle_call({:add_event, attrs}, _from, state) do
    event =
      attrs
      |> Map.put_new("emitted_count", 0)
      |> Map.put_new("last_emitted_at", nil)

    case EventSupervisor.start_child(%{event: event}) do
      {:ok, pid} ->
        Process.monitor(pid)

        next_state =
          put_in(state.event_pids[event["id"]], pid)

        {:reply, {:ok, event}, next_state}

      {:error, {:already_started, pid}} ->
        Process.monitor(pid)

        next_state =
          put_in(state.event_pids[event["id"]], pid)

        {:reply, {:ok, EventEmitter.status(pid)}, next_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:remove_event, event_id}, _from, state) do
    case Map.fetch(state.event_pids, event_id) do
      {:ok, pid} ->
        :ok = EventSupervisor.terminate_child(pid)
        {:reply, :ok, %{state | event_pids: Map.delete(state.event_pids, event_id)}}

      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call(:reset, _from, state) do
    Enum.each(state.event_pids, fn {_event_id, pid} ->
      :ok = EventSupervisor.terminate_child(pid)
    end)

    {:reply, :ok, %{state | event_pids: %{}}}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    next_event_pids =
      Map.reject(state.event_pids, fn {_event_id, emitter_pid} -> emitter_pid == pid end)

    {:noreply, %{state | event_pids: next_event_pids}}
  end
end
