defmodule FirehoseSimulatorWeb.FirehoseControlLive do
  use FirehoseSimulatorWeb, :live_view

  alias FirehoseSimulator.Firehose
  alias FirehoseSimulatorWeb.FirehoseEventForm

  def mount(_params, _session, socket) do
    if connected?(socket), do: Process.send_after(self(), :refresh_status, 500)

    status = Firehose.status()

    {:ok,
     assign(socket,
       event_form: FirehoseEventForm.form(),
       event_type_options: FirehoseEventForm.type_options(),
       events_count: status.events_count,
       last_event_at: status.last_event_at,
       events: status.events
     )}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="mx-auto w-full max-w-5xl space-y-8">
        <div class="space-y-4">
          <h2 class="text-2xl font-semibold">Firehose Control</h2>
          <div><strong>Published events:</strong> {@events_count}</div>
          <div><strong>Last event at:</strong> {@last_event_at || "n/a"}</div>
        </div>

        <section class="space-y-4 rounded-box border border-base-300 bg-base-100 p-6 shadow-sm">
          <.header>
            Configure events
          </.header>

          <.form
            for={@event_form}
            id="event-config-form"
            phx-change="change_event_form"
            phx-submit="add_event"
            class="grid gap-4 lg:grid-cols-2"
          >
            <.input
              field={@event_form[:type]}
              type="select"
              label="Event type"
              options={@event_type_options}
            />

            <div class="flex items-end">
              <.input field={@event_form[:random]} type="checkbox" label="Generate random data" />
            </div>

            <%= if FirehoseEventForm.manual?(@event_form) do %>
              <.input
                :if={FirehoseEventForm.follow?(@event_form)}
                field={@event_form[:author_did]}
                type="text"
                label="Author DID"
                placeholder="did:plc:..."
              />
              <.input
                :if={FirehoseEventForm.follow?(@event_form)}
                field={@event_form[:subject_did]}
                type="text"
                label="Subject DID"
                placeholder="did:plc:..."
              />

              <.input
                :if={FirehoseEventForm.post?(@event_form)}
                field={@event_form[:author_did]}
                type="text"
                label="Author DID"
                placeholder="did:plc:..."
              />
              <.input
                :if={FirehoseEventForm.post?(@event_form)}
                field={@event_form[:text]}
                type="textarea"
                label="Post text"
                rows="4"
                placeholder="Write a simulated post"
                class="w-full textarea lg:col-span-2"
              />
            <% end %>

            <div class="lg:col-span-2 flex justify-end">
              <.button type="submit" variant="primary">Save Event</.button>
            </div>
          </.form>
        </section>

        <section class="space-y-4 rounded-box border border-base-300 bg-base-100 p-6 shadow-sm">
          <.header>
            Configured event rows
            <:subtitle>Each configured row is emitted on every firehose tick.</:subtitle>
          </.header>

          <div
            :if={@events == []}
            id="configured-events-empty"
            class="rounded-box border border-dashed border-base-300 bg-base-200/50 px-4 py-8 text-center text-sm text-base-content/70"
          >
            No events configured yet.
          </div>

          <.table
            :if={@events != []}
            id="configured-events"
            rows={@events}
            row_id={fn row -> "configured-event-#{row["id"]}" end}
          >
            <:col :let={row} label="Type">{row["type"]}</:col>
            <:col :let={row} label="Mode">{if row["random"], do: "Random", else: "Manual"}</:col>
            <:col :let={row} label="Emitted">{row["emitted_count"]}</:col>
            <:col :let={row} label="Author DID">{row["author_did"] || "Generated at emit time"}</:col>
            <:col :let={row} label="Details">{event_details(row)}</:col>
          </.table>
        </section>
      </section>
    </Layouts.app>
    """
  end

  def handle_event("change_event_form", %{"event_config" => params}, socket) do
    {:noreply, assign(socket, :event_form, FirehoseEventForm.form(params))}
  end

  def handle_event("add_event", %{"event_config" => params}, socket) do
    case FirehoseEventForm.validate(params) do
      {:ok, event} ->
        {:ok, _event} = Firehose.add_event(event)
        status = Firehose.status()

        {:noreply,
         socket
         |> assign(:events, status.events)
         |> assign(:event_form, FirehoseEventForm.form())
         |> assign(:events_count, status.events_count)
         |> assign(:last_event_at, status.last_event_at)
         |> put_flash(:info, "Configured event saved")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :event_form, FirehoseEventForm.form_from_changeset(changeset))}
    end
  end

  def handle_info(:refresh_status, socket) do
    status = Firehose.status()
    Process.send_after(self(), :refresh_status, 500)

    {:noreply,
     assign(socket,
       events_count: status.events_count,
       last_event_at: status.last_event_at,
       events: status.events
     )}
  end

  defp event_details(%{"type" => "app.bsky.graph.follow", "random" => true}),
    do: "Subject DID generated at emit time"

  defp event_details(%{"type" => "app.bsky.feed.post", "random" => true}),
    do: "Post content generated at emit time"

  defp event_details(%{"type" => "app.bsky.graph.follow"} = row), do: row["subject_did"]
  defp event_details(%{"type" => "app.bsky.feed.post"} = row), do: row["text"]
end
