defmodule FirehoseSimulatorWeb.SetupLive do
  use FirehoseSimulatorWeb, :live_view

  require Logger

  alias FirehoseSimulator.Metrics
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
      |> assign(
        :generate_form,
        to_form(%{"db_connection_string" => state.db_connection_string}, as: :generate)
      )
      |> assign(
        :import_form,
        to_form(%{"db_connection_string" => state.db_connection_string}, as: :import)
      )
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
        %{"generate" => %{"db_connection_string" => connection_string} = params},
        socket
      ) do
    connection_string = String.trim(connection_string)

    with :ok <- ensure_upload_completed(socket, :userbase, "userbase"),
         :ok <- validate_connection_string(connection_string),
         {:ok, userbase_path} <- consume_json_upload(socket, :userbase),
         :ok <- State.put_db_connection_string(connection_string) do
      {:noreply,
       socket
       |> assign(:creating_userbase?, true)
       |> assign(:generate_form, to_form(params, as: :generate))
       |> start_async(:create_userbase, fn ->
         simulator_module().create_userbase(userbase_path, connection_string)
       end)}
    else
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to create userbase: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("validate_import", %{"import" => params}, socket) do
    {:noreply, assign(socket, :import_form, to_form(params, as: :import))}
  end

  def handle_event("validate_import", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event(
        "import_userbase",
        %{"import" => %{"db_connection_string" => connection_string} = params},
        socket
      ) do
    connection_string = String.trim(connection_string)

    with :ok <- ensure_upload_completed(socket, :userbase_meta, "userbase meta"),
         :ok <- validate_connection_string(connection_string),
         {:ok, meta_path} <- consume_json_upload(socket, :userbase_meta),
         :ok <- State.put_db_connection_string(connection_string) do
      {:noreply,
       socket
       |> assign(:importing_userbase?, true)
       |> assign(:import_form, to_form(params, as: :import))
       |> start_async(:import_userbase, fn ->
         simulator_module().import_userbase_from_csv(meta_path, connection_string)
       end)}
    else
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to import userbase: #{inspect(reason)}")}
    end
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

  defp validate_connection_string(""), do: {:error, "DB connection string cannot be empty"}
  defp validate_connection_string(_connection_string), do: :ok

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
           Logger.info("loaded json file: #{entry.client_name} -> #{copied_path}")

           :ok =
             Metrics.increment(:json_files_loaded, %{
               filename: entry.client_name,
               path: copied_path,
               kind: json_file_kind(upload_name)
             })

           {:ok, copied_path}
         end) do
      [copied_path] ->
        {:ok, copied_path}

      [] ->
        {:error, "Please upload a JSON file first"}
    end
  end

  defp copy_upload_to_tmp(source_path, entry) do
    extension = Path.extname(entry.client_name)
    tmp_name = "firehose-sim-#{upload_token()}#{extension}"
    tmp_path = Path.join(System.tmp_dir!(), tmp_name)
    File.cp!(source_path, tmp_path)
    tmp_path
  end

  defp upload_token do
    System.unique_integer([:positive, :monotonic])
  end

  defp simulator_module do
    Application.get_env(:firehose_simulator, :simulator_module, FirehoseSimulator)
  end

  defp json_file_kind(:userbase), do: "userbase"
  defp json_file_kind(:userbase_meta), do: "userbase_meta"
  defp json_file_kind(_upload_name), do: "unknown"
end
