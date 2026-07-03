defmodule FirehoseSimulatorWeb.SyncSocket do
  @behaviour Phoenix.Socket.Transport

  alias Phoenix.PubSub
  require Logger

  def child_spec(_opts) do
    :ignore
  end

  def connect(state) do
    subscribe_to_firehose()

    {:ok, state}
  end

  def init(state) do
    {:ok, state}
  end

  def handle_in({text, _opts}, state) do
    # for ping/pong
    {:reply, :ok, {:text, text}, state}
  end

  def handle_info(event, state) do
    {:push, {:binary, event}, state}
  end

  def terminate(_reason, _state) do
    :ok
  end

  defp subscribe_to_firehose do
    case PubSub.subscribe(FirehoseSimulator.PubSub, "firehose") do
      :ok -> Logger.debug("[SyncSocket] connected")
      {:error, error} -> Logger.error("[SyncSocket] #{error}")
    end
  end
end
