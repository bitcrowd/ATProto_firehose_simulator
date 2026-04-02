defmodule FirehoseSimulatorWeb.PlanningLive do
  use FirehoseSimulatorWeb, :live_view

  require Logger

  alias FirehoseSimulator.Metrics
  alias FirehoseSimulator.SimulationPlan
  alias FirehoseSimulator.State

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:current_path, ~p"/planning")
      |> assign(:current_scope, nil)
      |> assign(:generate_form, to_form(%{"plan_name" => ""}, as: :generate))
      |> assign(:import_form, to_form(%{"plan_name" => ""}, as: :import))
      |> assign(:last_action, nil)
      |> assign_plans()
      |> allow_upload(:simulation_plan_params_json,
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
  def handle_event("generate_plan", %{"generate" => params}, socket) do
    socket = assign(socket, :generate_form, to_form(params, as: :generate))

    with :ok <-
           ensure_upload_completed(socket, :simulation_plan_params_json, "simulation plan params"),
         {:ok, params_path, filename} <- consume_json_upload(socket, :simulation_plan_params_json),
         {:ok, simulation_plan} <-
           simulator_module().generate_simulation_plan_from_json(
             simulation_plan_params: params_path
           ) do
      plan_id = build_plan_id(params["plan_name"], filename)
      :ok = State.put_simulation_plan(plan_id, simulation_plan)

      {:noreply,
       socket
       |> assign(:last_action, "Generated plan #{plan_id}.")
       |> assign(:generate_form, to_form(%{"plan_name" => ""}, as: :generate))
       |> assign_plans()
       |> put_flash(:info, "Simulation plan generated.")}
    else
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to generate plan: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("import_plan", %{"import" => params}, socket) do
    socket = assign(socket, :import_form, to_form(params, as: :import))

    with :ok <- ensure_upload_completed(socket, :simulation_plan_json, "simulation plan"),
         {:ok, simulation_plan_path, filename} <-
           consume_json_upload(socket, :simulation_plan_json),
         {:ok, simulation_plan} <-
           simulator_module().import_simulation_plan_from_json(simulation_plan_path) do
      plan_id = build_plan_id(params["plan_name"], filename)
      :ok = State.put_simulation_plan(plan_id, simulation_plan)

      {:noreply,
       socket
       |> assign(:last_action, "Imported plan #{plan_id}.")
       |> assign(:import_form, to_form(%{"plan_name" => ""}, as: :import))
       |> assign_plans()
       |> put_flash(:info, "Simulation plan imported.")}
    else
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to import plan: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("delete_plan", %{"plan_id" => plan_id}, socket) do
    :ok = State.delete_simulation_plan(plan_id)

    {:noreply,
     socket
     |> assign(:last_action, "Deleted plan #{plan_id}.")
     |> assign_plans()
     |> put_flash(:info, "Simulation plan deleted.")}
  end

  @impl true
  def handle_event("export_plan", %{"plan_id" => plan_id}, socket) do
    with {:ok, simulation_plan} <- fetch_plan(plan_id),
         {:ok, json} <- SimulationPlan.to_json(simulation_plan) do
      filename = export_filename(plan_id)

      socket =
        push_event(socket, "save_simulation_plan_json", %{filename: filename, content: json})

      {:noreply,
       socket
       |> assign(:last_action, "Exported plan #{plan_id}.")
       |> put_flash(:info, "Simulation plan exported.")}
    else
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to export plan: #{inspect(reason)}")}
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

           :ok =
             Metrics.increment(:json_files_loaded, %{
               filename: entry.client_name,
               path: copied_path,
               kind: file_kind
             })

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
    tmp_name = "firehose-plan-#{upload_token()}#{extension}"
    tmp_path = Path.join(System.tmp_dir!(), tmp_name)
    File.cp!(source_path, tmp_path)
    tmp_path
  end

  defp upload_token do
    System.unique_integer([:positive, :monotonic])
  end

  defp assign_plans(socket) do
    plans =
      State.list_simulation_plans()
      |> Enum.map(fn {id, simulation_plan} ->
        %{
          id: id,
          simulation_plan: simulation_plan
        }
      end)
      |> Enum.sort_by(& &1.id, :desc)

    socket
    |> assign(:plans, plans)
  end

  defp fetch_plan(plan_id) when is_binary(plan_id) do
    case State.list_simulation_plans() do
      %{^plan_id => %SimulationPlan{} = simulation_plan} -> {:ok, simulation_plan}
      _other -> {:error, "Simulation plan #{plan_id} not found"}
    end
  end

  defp build_plan_id(plan_name, filename) do
    base =
      case String.trim(plan_name || "") do
        "" -> filename |> Path.rootname() |> String.trim()
        trimmed -> trimmed
      end

    slug =
      base
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/u, "-")
      |> String.trim("-")
      |> case do
        "" -> "plan"
        value -> value
      end

    "#{slug}-#{upload_token()}"
  end

  defp export_filename(plan_id) do
    sanitized =
      plan_id
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9_-]+/u, "-")
      |> String.trim("-")
      |> case do
        "" -> "simulation-plan"
        value -> value
      end

    "#{sanitized}.json"
  end

  defp simulator_module do
    Application.get_env(:firehose_simulator, :simulator_module, FirehoseSimulator)
  end

  defp json_file_kind(:simulation_plan_params_json), do: "simulation_plan_params"
  defp json_file_kind(:simulation_plan_json), do: "simulation_plan"
  defp json_file_kind(_upload_name), do: "unknown"
end
