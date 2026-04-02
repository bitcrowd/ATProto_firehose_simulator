defmodule FirehoseSimulatorWeb.MetricsLive do
  use FirehoseSimulatorWeb, :live_view

  alias FirehoseSimulator.Metrics

  @refresh_interval_ms 1_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      :timer.send_interval(@refresh_interval_ms, :refresh_metrics)
    end

    {:ok,
     socket
     |> assign(:current_path, ~p"/metrics")
     |> assign(:current_scope, nil)
     |> assign(:metrics, Metrics.snapshot())}
  end

  @impl true
  def handle_info(:refresh_metrics, socket) do
    {:noreply, assign(socket, :metrics, Metrics.snapshot())}
  end
end
