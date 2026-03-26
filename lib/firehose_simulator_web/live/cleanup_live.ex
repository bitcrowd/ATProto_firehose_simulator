defmodule FirehoseSimulatorWeb.CleanupLive do
  use FirehoseSimulatorWeb, :live_view

  alias FirehoseSimulator.Cleanup.Postgres
  alias FirehoseSimulator.Data
  alias FirehoseSimulatorWeb.CleanupForm

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Cleanup")
     |> assign(
       cleanup_form: CleanupForm.form(),
       cleanup_preview: nil,
       cleanup_result: nil,
       preview_database_url: nil
     )}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path={~p"/cleanup"}>
      <section class="mx-auto w-full max-w-5xl space-y-8">
        <div class="space-y-3">
          <h2 class="text-2xl font-semibold">Cleanup</h2>
          <p id="cleanup-notice" class="max-w-3xl text-sm leading-6 text-base-content/75">
            {Data.cleanup_notice()}
          </p>
        </div>

        <section class="rounded-[2rem] border border-base-300 bg-base-100 p-6 shadow-sm">
          <.form
            for={@cleanup_form}
            id="cleanup-form"
            phx-change="validate_cleanup"
            phx-submit="preview_cleanup"
            class="space-y-6"
          >
            <.input
              field={@cleanup_form[:database_url]}
              type="text"
              id="cleanup-database-url"
              label="Postgres connection string"
              placeholder="postgres://user:pass@host:5432/db"
            />

            <div class="flex flex-wrap items-center gap-3">
              <.button id="preview-cleanup-button" type="submit" variant="primary">
                Preview cleanup
              </.button>

              <.button
                :if={ready_to_execute?(@cleanup_form, @preview_database_url, @cleanup_preview)}
                id="run-cleanup-button"
                type="button"
                phx-click="execute_cleanup"
              >
                Run cleanup
              </.button>
            </div>
          </.form>
        </section>

        <section
          :if={@cleanup_preview}
          id="cleanup-preview-results"
          class="space-y-4 rounded-[2rem] border border-base-300 bg-base-100 p-6 shadow-sm"
        >
          <.header>
            Preview
            <:subtitle>Only exact simulator markers are eligible for deletion.</:subtitle>
          </.header>

          <%= for rule <- @cleanup_preview.matched_rules do %>
            <article class="rounded-2xl border border-base-300 bg-base-200/50 p-4">
              <div class="flex flex-wrap items-center justify-between gap-2">
                <h3 class="font-semibold">{rule.table}</h3>
                <span class="rounded-full bg-base-100 px-3 py-1 text-xs font-medium">
                  {rule.preview_count} rows
                </span>
              </div>
              <p class="mt-2 text-sm text-base-content/70">{rule.description}</p>
              <p class="mt-2 text-xs uppercase tracking-[0.24em] text-base-content/50">
                Column: {rule.column}
              </p>
            </article>
          <% end %>

          <div :if={@cleanup_preview.skipped_rules != []} id="cleanup-skipped-rules" class="space-y-2">
            <h3 class="text-sm font-semibold uppercase tracking-[0.24em] text-base-content/60">
              Skipped rules
            </h3>
            <%= for rule <- @cleanup_preview.skipped_rules do %>
              <p class="text-sm text-base-content/70">{rule.description}</p>
            <% end %>
          </div>

          <div :if={@cleanup_preview.warnings != []} id="cleanup-preview-warnings" class="space-y-2">
            <%= for warning <- @cleanup_preview.warnings do %>
              <p class="rounded-2xl border border-warning/40 bg-warning/10 px-4 py-3 text-sm text-base-content/80">
                {warning}
              </p>
            <% end %>
          </div>
        </section>

        <section
          :if={@cleanup_result}
          id="cleanup-execution-results"
          class="space-y-4 rounded-[2rem] border border-base-300 bg-base-100 p-6 shadow-sm"
        >
          <.header>
            Cleanup Results
          </.header>

          <%= for rule <- @cleanup_result.matched_rules do %>
            <div class="flex items-center justify-between rounded-2xl border border-base-300 bg-base-200/50 px-4 py-3 text-sm">
              <span>{rule.table} via {rule.column}</span>
              <span class="font-semibold">
                {Map.get(@cleanup_result.deleted_counts, rule.id, 0)} deleted
              </span>
            </div>
          <% end %>
        </section>
      </section>
    </Layouts.app>
    """
  end

  def handle_event("validate_cleanup", %{"cleanup" => params}, socket) do
    form =
      params
      |> CleanupForm.validate()
      |> case do
        {:ok, _database_url} -> CleanupForm.form(params)
        {:error, changeset} -> CleanupForm.from_changeset(changeset)
      end

    {:noreply,
     socket
     |> assign(:cleanup_form, form)
     |> maybe_reset_preview(params)}
  end

  def handle_event("preview_cleanup", %{"cleanup" => params}, socket) do
    case CleanupForm.validate(params) do
      {:ok, database_url} ->
        case Postgres.preview(database_url) do
          {:ok, report} ->
            {:noreply,
             socket
             |> assign(:cleanup_form, CleanupForm.form(params))
             |> assign(:cleanup_preview, report)
             |> assign(:cleanup_result, nil)
             |> assign(:preview_database_url, database_url)
             |> put_flash(:info, "Cleanup preview completed")}

          {:error, message} ->
            {:noreply,
             socket
             |> assign(:cleanup_form, CleanupForm.form(params))
             |> assign(:cleanup_preview, nil)
             |> assign(:cleanup_result, nil)
             |> assign(:preview_database_url, nil)
             |> put_flash(:error, message)}
        end

      {:error, changeset} ->
        {:noreply, assign(socket, :cleanup_form, CleanupForm.from_changeset(changeset))}
    end
  end

  def handle_event("execute_cleanup", _params, socket) do
    database_url = socket.assigns.preview_database_url

    if ready_to_execute?(
         socket.assigns.cleanup_form,
         database_url,
         socket.assigns.cleanup_preview
       ) do
      case Postgres.execute(database_url) do
        {:ok, report} ->
          {:noreply,
           socket
           |> assign(:cleanup_result, report)
           |> put_flash(:info, "Cleanup completed")}

        {:error, message} ->
          {:noreply, put_flash(socket, :error, message)}
      end
    else
      {:noreply,
       put_flash(socket, :error, "Preview the current database URL before running cleanup")}
    end
  end

  defp maybe_reset_preview(socket, params) do
    current_url = Map.get(params, "database_url", "") |> String.trim()

    if current_url == socket.assigns.preview_database_url do
      socket
    else
      socket
      |> assign(:cleanup_preview, nil)
      |> assign(:cleanup_result, nil)
      |> assign(:preview_database_url, nil)
    end
  end

  defp ready_to_execute?(cleanup_form, preview_database_url, preview) do
    current_url =
      cleanup_form.params
      |> Map.get("database_url", "")
      |> String.trim()

    is_binary(preview_database_url) and preview != nil and current_url == preview_database_url
  end
end
