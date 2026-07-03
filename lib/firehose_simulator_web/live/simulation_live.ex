defmodule FirehoseSimulatorWeb.SimulationLive do
  use FirehoseSimulatorWeb, :live_view
  alias FirehoseSimulator.State

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:current_path, ~p"/simulation")
      |> assign(:current_scope, nil)
      |> assign(:scenario_ids, [])
      |> assign(:selected_scenario_id, nil)
      |> assign(:load_form, to_form(%{"offset_ms" => "0"}, as: :load))
      |> assign(:players, [])
      |> assign(:current_simulation_plan, nil)
      |> assign(:last_action, nil)
      |> assign_players()
      |> assign_current_simulation_plan()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, assign_scenarios(socket, params["scenario_id"])}
  end

  @impl true
  def handle_event("validate_load", %{"load" => params}, socket) do
    {:noreply, assign(socket, :load_form, to_form(params, as: :load))}
  end

  def handle_event("validate_load", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("load", %{"load" => params}, socket) do
    socket = assign(socket, :load_form, to_form(params, as: :load))

    with {:ok, offset_ms} <- parse_offset_ms(params),
         {:ok, selected_scenario} <- fetch_selected_scenario(socket),
         {:ok, player_id, _metadata} <-
           FirehoseSimulator.load_with_offset(
             selected_scenario.scenario,
             offset_ms,
             scenario_id: selected_scenario.id
           ),
         {:ok, simulation_plan} <-
           FirehoseSimulator.add_and_play_scenario(
             selected_scenario.id,
             selected_scenario.scenario,
             offset_ms,
             selected_scenario.scenario.source_path
           ) do
      {:noreply,
       socket
       |> assign_players()
       |> assign_current_simulation_plan(simulation_plan)
       |> assign(
         :last_action,
         "Simulation loaded for #{player_id} with #{offset_ms} ms offset."
       )
       |> put_flash(:info, "Simulation loaded for #{player_id}.")}
    else
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, format_load_error(reason))}
    end
  end

  def handle_event("load", _params, socket) do
    {:noreply, put_flash(socket, :error, "Invalid load form payload.")}
  end

  def handle_event("start", %{"player_id" => player_id}, socket) do
    case FirehoseSimulator.start(player_id) do
      :ok ->
        {:noreply,
         socket
         |> assign_players()
         |> assign(:last_action, "Simulation started for #{player_id}.")
         |> put_flash(:info, "Simulation started for #{player_id}.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to start simulation: #{inspect(reason)}")}
    end
  end

  def handle_event("pause", %{"player_id" => player_id}, socket) do
    case FirehoseSimulator.pause(player_id) do
      :ok ->
        {:noreply,
         socket
         |> assign_players()
         |> assign(:last_action, "Simulation paused for #{player_id}.")
         |> put_flash(:info, "Simulation paused for #{player_id}.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to pause simulation: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("stop", %{"player_id" => player_id}, socket) do
    case FirehoseSimulator.stop(player_id) do
      :ok ->
        {:noreply,
         socket
         |> assign_players()
         |> assign(:last_action, "Simulation stopped for #{player_id}.")
         |> put_flash(:info, "Simulation stopped for #{player_id}.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to stop simulation: #{inspect(reason)}")}
    end
  end

  def handle_event("stop", _params, socket) do
    {:noreply, put_flash(socket, :error, "Missing player id to stop.")}
  end

  @impl true
  def handle_event("stop_all", _params, socket) do
    :ok = FirehoseSimulator.stop()

    {:noreply,
     socket
     |> assign_players()
     |> assign(:last_action, "All simulation players stopped.")
     |> put_flash(:info, "All simulation players stopped.")}
  end

  defp assign_scenarios(socket, selected_scenario_id) do
    scenario_ids =
      State.list_scenarios()
      |> Map.keys()
      |> Enum.sort(:desc)

    selected_scenario_id =
      if selected_scenario_id in scenario_ids, do: selected_scenario_id, else: nil

    socket
    |> assign(:scenario_ids, scenario_ids)
    |> assign(:selected_scenario_id, selected_scenario_id)
  end

  defp parse_offset_ms(params) when is_map(params) do
    value = params["offset_ms"] |> to_string() |> String.trim()

    case Integer.parse(value) do
      {offset_ms, ""} ->
        {:ok, offset_ms}

      _other ->
        {:error, "Offset must be an integer number of milliseconds."}
    end
  end

  defp format_load_error(reason) when is_binary(reason), do: reason
  defp format_load_error(reason), do: "Failed to load simulation: #{inspect(reason)}"

  defp fetch_selected_scenario(socket) do
    case socket.assigns.selected_scenario_id do
      nil ->
        {:error, "Select a scenario before loading."}

      scenario_id ->
        case State.list_scenarios() do
          %{^scenario_id => scenario} ->
            {:ok, %{id: scenario_id, scenario: scenario}}

          _ ->
            {:error, "Selected scenario is no longer available."}
        end
    end
  end

  defp assign_players(socket) do
    players =
      State.list_players()
      |> Enum.map(fn {player_id, metadata} -> %{player_id: player_id, metadata: metadata} end)
      |> Enum.sort_by(fn %{metadata: metadata} ->
        {sort_order(metadata.lifecycle_state), -Map.get(metadata, :loaded_at, 0)}
      end)

    assign(socket, :players, players)
  end

  defp sort_order(:running), do: 0
  defp sort_order(:paused), do: 1
  defp sort_order(:loaded), do: 2
  defp sort_order(_other), do: 3

  defp scenario_for_id(scenario_id) do
    State.list_scenarios()
    |> Map.get(scenario_id)
  end

  defp assign_current_simulation_plan(
         socket,
         simulation_plan \\ State.get_simulation_plan()
       ) do
    assign(socket, :current_simulation_plan, simulation_plan)
  end
end
