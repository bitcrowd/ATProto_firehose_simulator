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
      |> assign(:play_form, to_form(%{"offset_ms" => "0"}, as: :play))
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
  def handle_event("validate_play", %{"play" => params}, socket) do
    {:noreply, assign(socket, :play_form, to_form(params, as: :play))}
  end

  def handle_event("validate_play", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("play", %{"play" => params}, socket) do
    socket = assign(socket, :play_form, to_form(params, as: :play))

    with {:ok, offset_ms} <- parse_offset_ms(params),
         {:ok, simulation_plan} <- fetch_selected_plan() do
      case simulator_module().play_with_offset(simulation_plan, offset_ms) do
        {:ok, result} ->
          player_ids = player_ids_from_play_result(result)
          :ok = State.put_player_ids(player_ids)

          {:noreply,
           socket
           |> assign(:player_ids, player_ids)
           |> assign(:last_action, "Simulation playback started with #{offset_ms} ms offset.")
           |> put_flash(:info, "Simulation started.")}

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
      |> Enum.map(fn {id, simulation_plan} ->
        %{id: id, simulation_plan: simulation_plan}
      end)
      |> Enum.sort_by(& &1.id, :desc)

    selected_plan_id = State.get_selected_simulation_plan_id()
    selected_plan = Enum.find(plans, &(&1.id == selected_plan_id))

    socket
    |> assign(:plans, plans)
    |> assign(:selected_plan_id, selected_plan_id)
    |> assign(:selected_plan, selected_plan)
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

  defp fetch_selected_plan do
    case State.get_selected_simulation_plan() do
      nil -> {:error, "Select a simulation plan before playing."}
      simulation_plan -> {:ok, simulation_plan}
    end
  end

  defp player_ids_from_play_result(result) when is_map(result) do
    result
    |> Enum.filter(fn {_key, value} -> is_pid(value) end)
    |> Map.new()
  end

  defp player_ids_from_play_result(_result), do: %{}
end
