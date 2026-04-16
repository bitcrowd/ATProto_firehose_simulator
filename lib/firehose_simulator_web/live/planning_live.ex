defmodule FirehoseSimulatorWeb.PlanningLive do
  use FirehoseSimulatorWeb, :live_view

  require Logger

  alias FirehoseSimulator.Scenario
  alias FirehoseSimulator.State

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:current_path, ~p"/planning")
      |> assign(:current_scope, nil)
      |> assign(:generate_form, to_form(%{"scenario_name" => ""}, as: :generate))
      |> assign(:import_form, to_form(%{"scenario_name" => ""}, as: :import))
      |> assign(:import_plan_form, to_form(%{}, as: :import_plan))
      |> assign(:last_action, nil)
      |> assign_scenarios()
      |> allow_upload(:scenario_params_json,
        accept: ~w(.json),
        max_entries: 1,
        auto_upload: true
      )
      |> allow_upload(:scenario_json,
        accept: ~w(.json),
        max_entries: 1,
        auto_upload: true
      )
      |> allow_upload(:simulation_plan_json,
        accept: ~w(.json),
        max_entries: 1,
        auto_upload: true
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("validate_generate", %{"generate" => params}, socket) do
    {:noreply, assign(socket, :generate_form, to_form(params, as: :generate))}
  end

  def handle_event("validate_generate", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("validate_import", %{"import" => params}, socket) do
    {:noreply, assign(socket, :import_form, to_form(params, as: :import))}
  end

  def handle_event("validate_import", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("generate_scenario", %{"generate" => params}, socket) do
    socket = assign(socket, :generate_form, to_form(params, as: :generate))

    with :ok <-
           ensure_upload_completed(
             socket,
             :scenario_params_json,
             "scenario params"
           ),
         {:ok, params_path, filename} <- consume_json_upload(socket, :scenario_params_json),
         {:ok, scenario} <-
           FirehoseSimulator.generate_scenario_from_json(scenario_params: params_path) do
      scenario_id = build_scenario_id(params["scenario_name"], filename)
      :ok = State.put_scenario(scenario_id, scenario)

      {:noreply,
       socket
       |> assign(:last_action, "Generated scenario #{scenario_id}.")
       |> assign(:generate_form, to_form(%{"scenario_name" => ""}, as: :generate))
       |> assign_scenarios()
       |> put_flash(:info, "Scenario generated.")}
    else
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to generate scenario: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("import_scenario", %{"import" => params}, socket) do
    socket = assign(socket, :import_form, to_form(params, as: :import))

    with :ok <- ensure_upload_completed(socket, :scenario_json, "scenario"),
         {:ok, scenario_path, filename} <-
           consume_json_upload(socket, :scenario_json),
         {:ok, scenario} <-
           FirehoseSimulator.import_scenario_from_json(scenario_path) do
      scenario_id = build_scenario_id(params["scenario_name"], filename)
      :ok = State.put_scenario(scenario_id, scenario)

      {:noreply,
       socket
       |> assign(:last_action, "Imported scenario #{scenario_id}.")
       |> assign(:import_form, to_form(%{"scenario_name" => ""}, as: :import))
       |> assign_scenarios()
       |> put_flash(:info, "Scenario imported.")}
    else
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to import scenario: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("validate_import_plan", %{"import_plan" => params}, socket) do
    {:noreply, assign(socket, :import_plan_form, to_form(params, as: :import_plan))}
  end

  def handle_event("validate_import_plan", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("import_simulation_plan", %{"import_plan" => params}, socket) do
    socket = assign(socket, :import_plan_form, to_form(params, as: :import_plan))

    with :ok <- ensure_upload_completed(socket, :simulation_plan_json, "simulation plan"),
         {:ok, plan_path, _filename} <- consume_json_upload(socket, :simulation_plan_json),
         {:ok, simulation_plan} <- FirehoseSimulator.import_simulation_plan_from_json(plan_path) do
      {:noreply,
       socket
       |> assign(
         :last_action,
         "Imported simulation plan with #{length(simulation_plan.entries)} entries."
       )
       |> assign(:import_plan_form, to_form(%{}, as: :import_plan))
       |> assign_scenarios()
       |> put_flash(:info, "Simulation plan imported.")}
    else
      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "Failed to import simulation plan: #{inspect(reason)}")}
    end
  end

  def handle_event("import_simulation_plan", _params, socket) do
    with :ok <- ensure_upload_completed(socket, :simulation_plan_json, "simulation plan"),
         {:ok, plan_path, _filename} <- consume_json_upload(socket, :simulation_plan_json),
         {:ok, simulation_plan} <- FirehoseSimulator.import_simulation_plan_from_json(plan_path) do
      {:noreply,
       socket
       |> assign(
         :last_action,
         "Imported simulation plan with #{length(simulation_plan.entries)} entries."
       )
       |> assign(:import_plan_form, to_form(%{}, as: :import_plan))
       |> assign_scenarios()
       |> put_flash(:info, "Simulation plan imported.")}
    else
      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "Failed to import simulation plan: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("delete_scenario", %{"scenario_id" => scenario_id}, socket) do
    :ok = State.delete_scenario(scenario_id)

    {:noreply,
     socket
     |> assign(:last_action, "Deleted scenario #{scenario_id}.")
     |> assign_scenarios()
     |> put_flash(:info, "Scenario deleted.")}
  end

  @impl true
  def handle_event("export_scenario", %{"scenario_id" => scenario_id}, socket) do
    with {:ok, scenario} <- fetch_scenario(scenario_id),
         {:ok, json} <- Scenario.to_json(scenario) do
      filename = export_filename(scenario_id)

      socket =
        push_event(socket, "save_scenario_json", %{filename: filename, content: json})

      {:noreply,
       socket
       |> assign(:last_action, "Exported scenario #{scenario_id}.")
       |> put_flash(:info, "Scenario exported.")}
    else
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to export scenario: #{inspect(reason)}")}
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
           file_kind = json_file_kind(upload_name)
           Logger.info("loaded json file: #{entry.client_name} -> #{copied_path} (#{file_kind})")

           :telemetry.execute(
             [:firehose_simulator, :json, :file, :loaded],
             %{count: 1},
             %{
               filename: entry.client_name,
               path: copied_path,
               kind: file_kind
             }
           )

           {:ok, {copied_path, entry.client_name}}
         end) do
      [{copied_path, filename}] ->
        {:ok, copied_path, filename}

      [] ->
        {:error, "Please upload a JSON file first"}
    end
  end

  defp copy_upload_to_tmp(source_path, entry) do
    extension = Path.extname(entry.client_name)
    tmp_name = "firehose-scenario-#{upload_token()}#{extension}"
    tmp_path = Path.join(System.tmp_dir!(), tmp_name)
    File.cp!(source_path, tmp_path)
    tmp_path
  end

  defp upload_token do
    System.unique_integer([:positive, :monotonic])
  end

  defp assign_scenarios(socket) do
    scenarios =
      State.list_scenarios()
      |> Enum.map(fn {id, scenario} ->
        %{
          id: id,
          scenario: scenario
        }
      end)
      |> Enum.sort_by(& &1.id, :desc)

    socket
    |> assign(:scenarios, scenarios)
  end

  defp fetch_scenario(scenario_id) when is_binary(scenario_id) do
    case State.list_scenarios() do
      %{^scenario_id => %Scenario{} = scenario} -> {:ok, scenario}
      _other -> {:error, "Scenario #{scenario_id} not found"}
    end
  end

  defp build_scenario_id(scenario_name, filename) do
    base =
      case String.trim(scenario_name || "") do
        "" -> filename |> Path.rootname() |> String.trim()
        trimmed -> trimmed
      end

    slug =
      base
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/u, "-")
      |> String.trim("-")
      |> case do
        "" -> "scenario"
        value -> value
      end

    "#{slug}-#{upload_token()}"
  end

  defp export_filename(scenario_id) do
    sanitized =
      scenario_id
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9_-]+/u, "-")
      |> String.trim("-")
      |> case do
        "" -> "scenario"
        value -> value
      end

    "#{sanitized}.json"
  end

  defp json_file_kind(:scenario_params_json), do: "scenario_params"
  defp json_file_kind(:scenario_json), do: "scenario"
  defp json_file_kind(:simulation_plan_json), do: "simulation_plan"
  defp json_file_kind(_upload_name), do: "unknown"
end
