defmodule FirehoseSimulatorWeb.SimulationLive do
  use FirehoseSimulatorWeb, :live_view

  alias FirehoseSimulator.State

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:current_path, ~p"/simulation")
      |> assign(:current_scope, nil)
      |> assign(:scenarios, [])
      |> assign(:selected_scenario, nil)
      |> assign(:play_form, to_form(%{"offset_ms" => "0"}, as: :play))
      |> assign(:running_players, [])
      |> assign(:last_action, nil)
      |> assign_running_players()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, assign_scenarios(socket, params["scenario_id"])}
  end

  @impl true
  def handle_event("validate_play", %{"play" => params}, socket) do
    {:noreply, assign(socket, :play_form, to_form(params, as: :play))}
  end

  def handle_event("validate_play", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("play", %{"play" => params}, socket) do
    socket = assign(socket, :play_form, to_form(params, as: :play))

    with {:ok, offset_ms} <- parse_offset_ms(params),
         {:ok, selected_scenario} <- fetch_selected_scenario(socket) do
      shifted_scenario = simulator_module().shift_scenario(selected_scenario.scenario, offset_ms)

      case simulator_module().play(
             shifted_scenario,
             scenario_id: selected_scenario.id
           ) do
        {:ok, player_id, _metadata} ->
          {:noreply,
           socket
           |> assign_running_players()
           |> assign(
             :last_action,
             "Simulation playback started for #{player_id} with #{offset_ms} ms offset."
           )
           |> put_flash(:info, "Simulation started for #{player_id}.")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed to start simulation: #{inspect(reason)}")}
      end
    else
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, reason)}
    end
  end

  def handle_event("play", _params, socket) do
    {:noreply, put_flash(socket, :error, "Invalid play form payload.")}
  end

  @impl true
  def handle_event("stop", %{"player_id" => player_id}, socket) do
    case simulator_module().stop(player_id) do
      :ok ->
        {:noreply,
         socket
         |> assign_running_players()
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
    case simulator_module().stop_all() do
      :ok ->
        {:noreply,
         socket
         |> assign_running_players()
         |> assign(:last_action, "All simulation players stopped.")
         |> put_flash(:info, "All simulation players stopped.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to stop all players: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("reset", %{"player_id" => player_id}, socket) do
    case simulator_module().reset(player_id) do
      :ok ->
        {:noreply,
         socket
         |> assign_running_players()
         |> assign(:last_action, "Simulation reset for #{player_id}.")
         |> put_flash(:info, "Simulation reset for #{player_id}.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to reset simulation: #{inspect(reason)}")}
    end
  end

  def handle_event("reset", _params, socket) do
    {:noreply, put_flash(socket, :error, "Missing player id to reset.")}
  end

  @impl true
  def handle_event("reset_all", _params, socket) do
    case simulator_module().reset_all() do
      :ok ->
        {:noreply,
         socket
         |> assign_running_players()
         |> assign(:last_action, "All simulation players reset.")
         |> put_flash(:info, "All simulation players reset.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to reset all players: #{inspect(reason)}")}
    end
  end

  defp assign_scenarios(socket, selected_scenario_id) do
    scenarios =
      State.list_scenarios()
      |> Enum.map(fn {id, scenario} ->
        %{id: id, scenario: scenario}
      end)
      |> Enum.sort_by(& &1.id, :desc)

    selected_scenario = Enum.find(scenarios, &(&1.id == selected_scenario_id))

    socket
    |> assign(:scenarios, scenarios)
    |> assign(:selected_scenario, selected_scenario)
  end

  defp simulator_module do
    Application.get_env(:firehose_simulator, :simulator_module, FirehoseSimulator)
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

  defp fetch_selected_scenario(socket) do
    case socket.assigns.selected_scenario do
      nil -> {:error, "Select a scenario before playing."}
      selected_scenario -> {:ok, selected_scenario}
    end
  end

  defp assign_running_players(socket) do
    running_players =
      State.list_running_players()
      |> Enum.map(fn {player_id, metadata} -> %{player_id: player_id, metadata: metadata} end)
      |> Enum.sort_by(fn %{metadata: metadata} -> Map.get(metadata, :started_at_ms, 0) end, :desc)

    assign(socket, :running_players, running_players)
  end
end
