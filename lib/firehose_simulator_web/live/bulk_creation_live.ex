defmodule FirehoseSimulatorWeb.BulkCreationLive do
  use FirehoseSimulatorWeb, :live_view

  alias FirehoseSimulator.BulkCreation
  alias FirehoseSimulatorWeb.BulkCreationConnectionForm
  alias FirehoseSimulatorWeb.BulkCreationJobForm

  def mount(_params, _session, socket) do
    bulk_state = BulkCreation.current_state()

    {:ok,
     socket
     |> assign(:connection_form, BulkCreationConnectionForm.form(connection_params(bulk_state)))
     |> assign(:follows_form, BulkCreationJobForm.form(:follows_job))
     |> assign(:posts_form, BulkCreationJobForm.form(:posts_job))
     |> assign(:bulk_state, bulk_state)
     |> assign(:job_results, %{})}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path={~p"/bulk-creation"}>
      <section class="mx-auto w-full max-w-6xl space-y-8">
        <section class="rounded-[1.75rem] border border-base-300 bg-base-100 p-6 shadow-sm">
          <.header>
            Database Connection
          </.header>

          <.form
            for={@connection_form}
            id="bulk-connection-form"
            phx-submit="connect"
            class="grid gap-4 lg:grid-cols-[1fr_auto] lg:items-end"
          >
            <.input
              field={@connection_form[:connection_string]}
              type="text"
              label="Postgres URL"
              placeholder="postgres://..."
              class="w-full input border-slate-300 bg-slate-50"
            />
            <.button type="submit" variant="primary" class="btn h-12 rounded-xl px-6">
              Connect
            </.button>
          </.form>
          <div class="mt-6 space-y-3 border-t border-slate-200 pt-6">
            <div class="space-y-1">
              <h3>
                Connection State
              </h3>
            </div>

            <dl class="grid gap-4 text-sm text-slate-700 md:grid-cols-2">
              <div class="flex items-center justify-between gap-4 rounded-2xl bg-slate-50 px-4 py-3">
                <dt class="text-slate-500">Connected</dt>
                <dd class={[
                  "rounded-full px-3 py-1 text-xs font-semibold",
                  @bulk_state.connected? && "bg-emerald-100 text-emerald-700",
                  !@bulk_state.connected? && "bg-slate-200 text-slate-600"
                ]}>
                  {if @bulk_state.connected?, do: "Yes", else: "No"}
                </dd>
              </div>
              <div class="rounded-2xl bg-slate-50 px-4 py-3">
                <dt class="text-slate-500">Connection string</dt>
                <dd
                  id="bulk-connection-string"
                  class="mt-1 break-all font-mono text-xs text-slate-700"
                >
                  {Map.get(@bulk_state, :connection_string, "Not connected")}
                </dd>
              </div>
              <div class="flex items-center justify-between gap-4 rounded-2xl bg-slate-50 px-4 py-3">
                <dt class="text-slate-500">Last user id</dt>
                <dd id="bulk-last-user-id" class="font-semibold text-slate-900">
                  {Map.get(@bulk_state, :last_user_id, 0)}
                </dd>
              </div>
              <div class="flex items-center justify-between gap-4 rounded-2xl bg-slate-50 px-4 py-3">
                <dt class="text-slate-500">Last post sequence</dt>
                <dd id="bulk-last-post-sequence" class="font-semibold text-slate-900">
                  {Map.get(@bulk_state, :last_post_sequence, 0)}
                </dd>
              </div>
            </dl>
          </div>
        </section>

        <div class="grid gap-6 xl:grid-cols-2">
          <section class="rounded-[1.75rem] border border-base-300 bg-base-100 p-6 shadow-sm">
            <.header>
              Follows
              <:subtitle>
                Generate a deterministic follower graph from the next reserved user IDs.
              </:subtitle>
            </.header>

            <.form
              for={@follows_form}
              id="bulk-follows-form"
              phx-submit="create_follows"
              class="space-y-5"
            >
              <.input
                field={@follows_form[:count]}
                type="number"
                label="Users in graph"
                min="1"
                class="w-full input border-slate-300 bg-slate-50"
              />

              <.button type="submit" variant="primary" class="btn h-12 rounded-xl px-6">
                Create Follows
              </.button>
            </.form>

            <.result_card id="follows-result" result={@job_results[:follows]} />
          </section>

          <section class="rounded-[1.75rem] border border-base-300 bg-base-100 p-6 shadow-sm">
            <.header>
              Posts
              <:subtitle>
                Generate a deterministic list of user IDs and create one post per generated author.
              </:subtitle>
            </.header>

            <.form for={@posts_form} id="bulk-posts-form" phx-submit="create_posts" class="space-y-5">
              <.input
                field={@posts_form[:count]}
                type="number"
                label="Authors to generate"
                min="1"
                class="w-full input border-slate-300 bg-slate-50"
              />

              <.button type="submit" variant="primary" class="btn h-12 rounded-xl px-6">
                Create Posts
              </.button>
            </.form>

            <.result_card id="posts-result" result={@job_results[:posts]} />
          </section>
        </div>
      </section>
    </Layouts.app>
    """
  end

  def handle_event("connect", %{"connection" => params}, socket) do
    case BulkCreationConnectionForm.validate(params) do
      {:ok, %{connection_string: connection_string}} ->
        case BulkCreation.connect(connection_string) do
          {:ok, bulk_state} ->
            {:noreply,
             socket
             |> assign(:bulk_state, Map.put(bulk_state, :connected?, true))
             |> assign(
               :connection_form,
               BulkCreationConnectionForm.form(%{"connection_string" => connection_string})
             )
             |> put_flash(:info, "Database connection established")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, reason)}
        end

      {:error, changeset} ->
        {:noreply,
         assign(
           socket,
           :connection_form,
           BulkCreationConnectionForm.form_from_changeset(changeset)
         )}
    end
  end

  def handle_event("create_follows", %{"follows_job" => params}, socket) do
    handle_job(socket, :follows, params, :follows_job, &BulkCreation.create_follows/1)
  end

  def handle_event("create_posts", %{"posts_job" => params}, socket) do
    handle_job(socket, :posts, params, :posts_job, &BulkCreation.create_posts/1)
  end

  attr :id, :string, required: true
  attr :result, :map, default: nil

  defp result_card(assigns) do
    ~H"""
    <div
      :if={@result}
      id={@id}
      class="mt-6 rounded-2xl border border-emerald-200 bg-emerald-50/70 p-4 text-sm text-emerald-900"
    >
      <p class="font-semibold">Last run inserted {@result.inserted_count} rows.</p>
      <p :if={Map.has_key?(@result, :last_user_id)} class="mt-1">
        Last user id: {@result.last_user_id}
      </p>
      <p :if={Map.has_key?(@result, :last_post_sequence)} class="mt-1">
        Last post sequence: {@result.last_post_sequence}
      </p>
    </div>
    """
  end

  defp handle_job(socket, type, params, form_name, create_fun) do
    case BulkCreationJobForm.validate(params) do
      {:ok, %{count: count}} ->
        case create_fun.(count) do
          {:ok, result} ->
            bulk_state = BulkCreation.current_state()

            {:noreply,
             socket
             |> assign(:bulk_state, bulk_state)
             |> assign(:job_results, Map.put(socket.assigns.job_results, type, result))
             |> assign(form_assign_name(form_name), BulkCreationJobForm.form(form_name))
             |> put_flash(:info, success_message(type, result.inserted_count))}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, reason)}
        end

      {:error, changeset} ->
        {:noreply,
         assign(
           socket,
           form_assign_name(form_name),
           BulkCreationJobForm.form_from_changeset(form_name, changeset)
         )}
    end
  end

  defp success_message(:follows, count), do: "Inserted #{count} follows"
  defp success_message(:posts, count), do: "Inserted #{count} posts"

  defp form_assign_name(:follows_job), do: :follows_form
  defp form_assign_name(:posts_job), do: :posts_form

  defp connection_params(%{connected?: true, connection_string: connection_string}) do
    %{"connection_string" => connection_string}
  end

  defp connection_params(_state), do: %{}
end
