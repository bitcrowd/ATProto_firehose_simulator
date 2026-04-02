defmodule FirehoseSimulatorWeb.SimulationLive do
  use FirehoseSimulatorWeb, :live_view

  alias FirehoseSimulator.State

  @impl true
  def mount(_params, _session, socket) do
    simulation_plan = State.get_simulation_plan()
    player_ids = State.get_player_ids()

    socket =
      socket
      |> assign(:current_path, ~p"/simulation")
      |> assign(:current_scope, nil)
      |> assign(:simulation_plan_loaded?, not is_nil(simulation_plan))
      |> assign(:player_ids, player_ids)
      |> assign(:last_action, nil)
      |> assign(:form, to_form(%{"time_offset_ms" => "0"}, as: :simulation))
      |> allow_upload(:simulation_plan_params_json,
        accept: ~w(.json),
        max_entries: 1,
        auto_upload: true
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("validate_plan", %{"simulation" => simulation_params}, socket) do
    {:noreply, assign(socket, :form, to_form(simulation_params, as: :simulation))}
  end

  def handle_event("validate_plan", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("create_plan", %{"simulation" => simulation_params}, socket) do
    socket = assign(socket, :form, to_form(simulation_params, as: :simulation))

    with :ok <-
           ensure_upload_completed(
             socket,
             :simulation_plan_params_json,
             "simulation plan params"
           ),
         {:ok, time_offset_ms} <- parse_time_offset_ms(simulation_params),
         {:ok, params_path} <- consume_json_upload(socket, :simulation_plan_params_json),
         {:ok, simulation_plan} <-
           simulator_module().load_simulation_plan_from_json(simulation_plan_params: params_path) do
      shifted_simulation_plan =
        simulator_module().shift_simulation_plan(simulation_plan, time_offset_ms)

      :ok = State.put_simulation_plan(shifted_simulation_plan)

      {:noreply,
       socket
       |> assign(:simulation_plan_loaded?, true)
       |> assign(
         :last_action,
         "Simulation plan created in memory with #{time_offset_ms} ms offset."
       )
       |> put_flash(:info, "Simulation plan loaded.")}
    else
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to create plan: #{inspect(reason)}")}
    end
  end

  def handle_event("play", _params, socket) do
    case State.get_simulation_plan() do
      nil ->
        {:noreply, put_flash(socket, :error, "Create a simulation plan before playing.")}

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

  def handle_event("reset", _params, socket) do
    case simulator_module().reset() do
      :ok ->
        :ok = State.clear_simulation_plan()
        :ok = State.clear_player_ids()

        {:noreply,
         socket
         |> assign(:simulation_plan_loaded?, false)
         |> assign(:player_ids, %{})
         |> assign(:last_action, "Simulation player reset.")
         |> put_flash(:info, "Simulation reset.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to reset simulation: #{inspect(reason)}")}
    end
  end

  defp ensure_upload_completed(socket, upload_name, label) do
    {completed_entries, in_progress_entries} = uploaded_entries(socket, upload_name)

    cond do
      completed_entries != [] ->
        :ok

      in_progress_entries != [] ->
        {:error, "Please wait for #{label} upload to finish"}

      true ->
        {:error, "Please upload #{label} JSON first"}
    end
  end

  defp consume_json_upload(socket, upload_name) do
    case consume_uploaded_entries(socket, upload_name, fn %{path: path}, entry ->
           copied_path = copy_upload_to_tmp(path, entry)
           {:ok, copied_path}
         end) do
      [copied_path] ->
        {:ok, copied_path}

      [] ->
        {:error, "Please upload simulation plan params JSON first"}
    end
  end

  defp copy_upload_to_tmp(source_path, entry) do
    extension = Path.extname(entry.client_name)
    tmp_name = "firehose-plan-#{upload_token()}#{extension}"
    tmp_path = Path.join(System.tmp_dir!(), tmp_name)
    File.cp!(source_path, tmp_path)
    tmp_path
  end

  defp upload_token do
    System.unique_integer([:positive, :monotonic])
  end

  defp parse_time_offset_ms(%{"time_offset_ms" => value}) when is_binary(value) do
    case String.trim(value) do
      "" ->
        {:ok, 0}

      trimmed ->
        parse_integer_offset(trimmed)
    end
  end

  defp parse_time_offset_ms(_params), do: {:ok, 0}

  defp parse_integer_offset(value) when is_binary(value) do
    case Integer.parse(value) do
      {offset_ms, ""} -> {:ok, offset_ms}
      _parse_error -> {:error, "Simulation offset must be a valid integer in milliseconds"}
    end
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
