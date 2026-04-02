defmodule FirehoseSimulatorWeb.SimulationLive do
  use FirehoseSimulatorWeb, :live_view

  alias FirehoseSimulator.State

  @impl true
  def mount(_params, _session, socket) do
    player_ids = State.get_player_ids()

    socket =
      socket
      |> assign(:current_path, ~p"/simulation")
      |> assign(:current_scope, nil)
      |> assign(:plans, [])
      |> assign(:selected_plan_id, nil)
      |> assign(:player_ids, player_ids)
      |> assign(:last_action, nil)
      |> assign_plans()

    {:ok, socket}
  end

  @impl true
  def handle_event("select_plan", %{"plan_id" => plan_id}, socket) do
    :ok = State.select_simulation_plan(plan_id)
    {:noreply, assign_plans(socket)}
  end

  @impl true
  def handle_event("play", _params, socket) do
    case State.get_selected_simulation_plan() do
      nil ->
        {:noreply, put_flash(socket, :error, "Select a simulation plan before playing.")}

      simulation_plan ->
        case simulator_module().play(simulation_plan) do
          {:ok, result} ->
            player_ids = player_ids_from_play_result(result)
            :ok = State.put_player_ids(player_ids)

            {:noreply,
             socket
             |> assign(:player_ids, player_ids)
             |> assign(:last_action, "Simulation playback started.")
             |> put_flash(:info, "Simulation started.")}

          {:error, reason} ->
            {:noreply,
             put_flash(socket, :error, "Failed to start simulation: #{inspect(reason)}")}
        end
    end
  end

  @impl true
  def handle_event("stop", _params, socket) do
    case simulator_module().stop() do
      :ok ->
        {:noreply,
         socket
         |> assign(:last_action, "Simulation stopped.")
         |> put_flash(:info, "Simulation stopped.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to stop simulation: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("reset", _params, socket) do
    case simulator_module().reset() do
      :ok ->
        :ok = State.clear_player_ids()

        {:noreply,
         socket
         |> assign(:player_ids, %{})
         |> assign(:last_action, "Simulation player reset.")
         |> put_flash(:info, "Simulation reset.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to reset simulation: #{inspect(reason)}")}
    end
  end

  defp assign_plans(socket) do
    plans =
      State.list_simulation_plans()
      |> Map.keys()
      |> Enum.sort(:desc)

    socket
    |> assign(:plans, plans)
    |> assign(:selected_plan_id, State.get_selected_simulation_plan_id())
  end

  defp simulator_module do
    Application.get_env(:firehose_simulator, :simulator_module, FirehoseSimulator)
  end

  defp player_ids_from_play_result(result) when is_map(result) do
    result
    |> Enum.filter(fn {_key, value} -> is_pid(value) end)
    |> Map.new()
  end

  defp player_ids_from_play_result(_result), do: %{}
end
