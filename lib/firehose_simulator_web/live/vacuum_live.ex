defmodule FirehoseSimulatorWeb.VacuumLive do
  use FirehoseSimulatorWeb, :live_view

  alias FirehoseSimulator.State

  @impl true
  def mount(_params, _session, socket) do
    state = State.get()

    socket =
      socket
      |> assign(:current_path, ~p"/vacuum")
      |> assign(:current_scope, nil)
      |> assign(:running_vacuum?, false)
      |> assign(:vacuum_result, nil)
      |> assign(:form, vacuum_form(state.db_connection_string))

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"vacuum" => params}, socket) do
    {:noreply, assign(socket, :form, to_form(params, as: :vacuum))}
  end

  @impl true
  def handle_event("run_vacuum", %{"vacuum" => params}, socket) do
    socket = assign(socket, :form, to_form(params, as: :vacuum))
    connection_string = String.trim(params["db_connection_string"] || "")
    delete_userbase? = truthy_param?(params["delete_userbase"])
    delete_posts? = truthy_param?(params["delete_posts"])

    with :ok <- validate_connection_string(connection_string),
         :ok <- validate_actions(delete_userbase?, delete_posts?),
         :ok <- State.put_db_connection_string(connection_string) do
      {:noreply,
       socket
       |> assign(:running_vacuum?, true)
       |> start_async(:run_vacuum, fn ->
         simulator_module().vacuum(
           connection_string,
           delete_userbase?: delete_userbase?,
           delete_posts?: delete_posts?
         )
       end)}
    else
      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:running_vacuum?, false)
         |> put_flash(:error, "Failed to run vacuum actions: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_async(:run_vacuum, {:ok, {:ok, result}}, socket) do
    {:noreply,
     socket
     |> assign(:running_vacuum?, false)
     |> assign(:vacuum_result, result)
     |> put_flash(:info, "Vacuum actions completed.")}
  end

  def handle_async(:run_vacuum, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:running_vacuum?, false)
     |> put_flash(:error, "Failed to run vacuum actions: #{inspect(reason)}")}
  end

  def handle_async(:run_vacuum, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:running_vacuum?, false)
     |> put_flash(:error, "Failed to run vacuum actions: #{inspect(reason)}")}
  end

  defp vacuum_form(connection_string) do
    to_form(
      %{
        "db_connection_string" => connection_string,
        "delete_userbase" => false,
        "delete_posts" => false
      },
      as: :vacuum
    )
  end

  defp validate_connection_string(""), do: {:error, "DB connection string cannot be empty"}
  defp validate_connection_string(_connection_string), do: :ok

  defp validate_actions(false, false),
    do: {:error, "Select at least one vacuum action"}

  defp validate_actions(_delete_userbase?, _delete_posts?), do: :ok

  defp truthy_param?(value) when value in [true, "true", "on", "1"], do: true
  defp truthy_param?(_value), do: false

  defp simulator_module do
    Application.get_env(:firehose_simulator, :simulator_module, FirehoseSimulator)
  end
end
