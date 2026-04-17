defmodule FirehoseSimulatorWeb.SetupLive do
  use FirehoseSimulatorWeb, :live_view

  require Logger

  alias FirehoseSimulator.State

  @impl true
  def mount(_params, _session, socket) do
    state = State.get()

    socket =
      socket
      |> assign(:current_path, ~p"/setup")
      |> assign(:current_scope, nil)
      |> assign(:state, state)
      |> assign(:creating_userbase?, false)
      |> assign(:importing_userbase?, false)
      |> assign(:generate_form, to_form(%{}, as: :generate))
      |> assign(:import_form, to_form(%{}, as: :import))
      |> allow_upload(:userbase, accept: ~w(.json), max_entries: 1, auto_upload: true)
      |> allow_upload(:userbase_meta, accept: ~w(.json), max_entries: 1, auto_upload: true)

    {:ok, socket}
  end

  @impl true
  def handle_event("validate_generate", %{"generate" => params}, socket) do
    {:noreply, assign(socket, :generate_form, to_form(params, as: :generate))}
  end

  def handle_event("validate_generate", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event(
        "create_userbase",
        %{"generate" => params},
        socket
      ) do
    with :ok <- ensure_upload_completed(socket, :userbase, "userbase"),
         {:ok, userbase_json} <- consume_json_upload(socket, :userbase) do
      {:noreply,
       socket
       |> assign(:creating_userbase?, true)
       |> assign(:generate_form, to_form(params, as: :generate))
       |> start_async(:create_userbase, fn ->
         FirehoseSimulator.create_userbase_from_json(userbase_json)
       end)}
    else
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to create userbase: #{inspect(reason)}")}
    end
  end

  def handle_event("create_userbase", _params, socket) do
    handle_event("create_userbase", %{"generate" => %{}}, socket)
  end

  @impl true
  def handle_event("validate_import", %{"import" => params}, socket) do
    {:noreply, assign(socket, :import_form, to_form(params, as: :import))}
  end

  def handle_event("validate_import", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event(
        "import_userbase",
        %{"import" => params},
        socket
      ) do
    with :ok <- ensure_upload_completed(socket, :userbase_meta, "userbase meta"),
         {:ok, meta_json} <- consume_json_upload(socket, :userbase_meta) do
      {:noreply,
       socket
       |> assign(:importing_userbase?, true)
       |> assign(:import_form, to_form(params, as: :import))
       |> start_async(:import_userbase, fn ->
         FirehoseSimulator.import_userbase_from_csv_json(meta_json)
       end)}
    else
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to import userbase: #{inspect(reason)}")}
    end
  end

  def handle_event("import_userbase", _params, socket) do
    handle_event("import_userbase", %{"import" => %{}}, socket)
  end

  @impl true
  def handle_async(:create_userbase, {:ok, {:ok, result}}, socket) do
    :ok = State.put_userbase_result(true, result)
    state = State.get()

    {:noreply,
     socket
     |> assign(:creating_userbase?, false)
     |> assign(:state, state)
     |> put_flash(:info, "Userbase created successfully.")}
  end

  def handle_async(:create_userbase, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:creating_userbase?, false)
     |> put_flash(:error, "Failed to create userbase: #{inspect(reason)}")}
  end

  def handle_async(:create_userbase, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:creating_userbase?, false)
     |> put_flash(:error, "Failed to create userbase: #{inspect(reason)}")}
  end

  def handle_async(:import_userbase, {:ok, {:ok, result}}, socket) do
    :ok = State.put_userbase_result(true, result)
    state = State.get()

    {:noreply,
     socket
     |> assign(:importing_userbase?, false)
     |> assign(:state, state)
     |> put_flash(:info, "Userbase imported successfully.")}
  end

  def handle_async(:import_userbase, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:importing_userbase?, false)
     |> put_flash(:error, "Failed to import userbase: #{inspect(reason)}")}
  end

  def handle_async(:import_userbase, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:importing_userbase?, false)
     |> put_flash(:error, "Failed to import userbase: #{inspect(reason)}")}
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
           {:ok, content} = File.read(path)
           Logger.info("loaded json file: #{entry.client_name} -> #{path}")

           :telemetry.execute(
             [:firehose_simulator, :json, :file, :loaded],
             %{count: 1},
             %{
               filename: entry.client_name,
               path: path,
               kind: json_file_kind(upload_name)
             }
           )

           {:ok, content}
         end) do
      [content] ->
        {:ok, content}

      [] ->
        {:error, "Please upload a JSON file first"}
    end
  end

  defp json_file_kind(:userbase), do: "userbase"
  defp json_file_kind(:userbase_meta), do: "userbase_meta"
  defp json_file_kind(_upload_name), do: "unknown"
end
