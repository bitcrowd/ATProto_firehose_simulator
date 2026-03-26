defmodule FirehoseSimulatorWeb.FirehoseControlLive do
  use FirehoseSimulatorWeb, :live_view

  alias FirehoseSimulator.Firehose
  alias FirehoseSimulator.Firehose.EventEmitter
  alias FirehoseSimulatorWeb.FirehoseEventForm

  def mount(_params, _session, socket) do
    events = Firehose.events()

    {:ok,
     socket
     |> assign(:page_title, "Firehose Control")
     |> assign(
       event_form: FirehoseEventForm.form(),
       event_type_options: FirehoseEventForm.type_options(),
       events: events
     )
     |> assign_event_totals()
     |> maybe_subscribe_to_events(events)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path={~p"/firehose"}>
      <section class="mx-auto w-full max-w-5xl space-y-8">
        <div class="space-y-4">
          <h2 class="text-2xl font-semibold">Firehose Control</h2>
          <div><strong>Published events:</strong> {@events_count}</div>
          <div><strong>Last event at:</strong> {@last_event_at || "n/a"}</div>
        </div>

        <.panel class="space-y-4">
          <.header>
            Configure events
          </.header>

          <.form
            for={@event_form}
            id="event-config-form"
            phx-change="change_event_form"
            phx-submit="add_event"
            class="space-y-6"
          >
            <.input
              field={@event_form[:type]}
              type="select"
              label="Event type"
              options={@event_type_options}
              class="w-full select select-bordered select-lg"
            />

            <div class="grid gap-4 md:grid-cols-2">
              <.input
                field={@event_form[:random]}
                type="checkbox"
                label="Generate random data"
              />

              <.input
                field={@event_form[:time_ms]}
                type="number"
                label="Emit every (ms)"
                min="1"
              />
            </div>

            <%= if FirehoseEventForm.manual?(@event_form) do %>
              <div class="grid gap-4 lg:grid-cols-2">
                <.input
                  :if={FirehoseEventForm.follow?(@event_form)}
                  field={@event_form[:author_did]}
                  type="text"
                  label="Author DID"
                  placeholder="did:plc:firesim123"
                />
                <.input
                  :if={FirehoseEventForm.follow?(@event_form)}
                  field={@event_form[:subject_did]}
                  type="text"
                  label="Subject DID"
                  placeholder="did:plc:firesim456"
                />

                <.input
                  :if={FirehoseEventForm.post?(@event_form)}
                  field={@event_form[:author_did]}
                  type="text"
                  label="Author DID"
                  placeholder="did:plc:firesim123"
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
              </div>

              <p class="text-sm text-base-content/70">
                Cleanup only removes rows that can be positively identified as simulator-owned, such
                as records authored by <code>did:sim:</code> identities.
              </p>
            <% end %>

            <div class="flex justify-end">
              <.button type="submit" variant="primary">Save Event</.button>
            </div>
          </.form>
        </.panel>

        <.panel class="space-y-4">
          <.header>
            Configured event rows
            <:subtitle>Each configured row emits independently on its own cadence.</:subtitle>
          </.header>

          <div
            :if={@events == []}
            id="configured-events-empty"
            class="rounded-box border border-dashed border-base-300 bg-base-200/50 px-4 py-8 text-center text-sm text-base-content/70"
          >
            No events configured yet.
          </div>

          <div :if={@events != []} id="configured-events" class="space-y-4">
            <.card
              :for={row <- @events}
              id={"configured-event-#{row["id"]}"}
              title={row["type"]}
              subtitle={if row["random"], do: "Random data", else: "Manual data"}
            >
              <:actions>
                <button
                  type="button"
                  id={"remove-event-#{row["id"]}"}
                  phx-click="remove_event"
                  phx-value-id={row["id"]}
                  class="link link-error no-underline hover:underline"
                >
                  Remove
                </button>
              </:actions>

              <dl class="mt-4 grid gap-4 md:grid-cols-2">
                <div class="space-y-1">
                  <dt class="text-xs font-semibold uppercase tracking-wide text-base-content/60">
                    Frequency
                  </dt>
                  <dd class="text-sm text-base-content">{"#{row["time_ms"]} ms"}</dd>
                </div>

                <div class="space-y-1">
                  <dt class="text-xs font-semibold uppercase tracking-wide text-base-content/60">
                    Emitted
                  </dt>
                  <dd class="text-sm text-base-content">{row["emitted_count"]}</dd>
                </div>

                <div class="space-y-1">
                  <dt class="text-xs font-semibold uppercase tracking-wide text-base-content/60">
                    Author DID
                  </dt>
                  <dd class="text-sm text-base-content">
                    {row["author_did"] || "Generated at emit time"}
                  </dd>
                </div>

                <div class="space-y-1">
                  <dt class="text-xs font-semibold uppercase tracking-wide text-base-content/60">
                    Details
                  </dt>
                  <dd class="text-sm text-base-content">{event_details(row)}</dd>
                </div>
              </dl>
            </.card>
          </div>
        </.panel>
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
        {:ok, event} = Firehose.add_event(event)

        {:noreply,
         socket
         |> assign(:events, socket.assigns.events ++ [event])
         |> assign_event_totals()
         |> subscribe_to_event(event)
         |> assign(:event_form, FirehoseEventForm.form())
         |> put_flash(:info, "Configured event saved")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :event_form, FirehoseEventForm.form_from_changeset(changeset))}
    end
  end

  def handle_event("remove_event", %{"id" => event_id}, socket) do
    event_id = String.to_integer(event_id)

    case Firehose.remove_event(event_id) do
      :ok ->
        filtered_events =
          Enum.reject(socket.assigns.events, fn event ->
            event["id"] == event_id
          end)

        {:noreply,
         socket
         |> assign(:events, filtered_events)
         |> assign_event_totals()
         |> put_flash(:info, "Configured event removed")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Configured event no longer exists")}
    end
  end

  def handle_info({:firehose_event_updated, updated_event}, socket) do
    {:noreply,
     socket
     |> assign(:events, replace_event(socket.assigns.events, updated_event))
     |> assign_event_totals()}
  end

  defp event_details(%{"type" => "app.bsky.graph.follow", "random" => true}),
    do: "Subject DID generated at emit time"

  defp event_details(%{"type" => "app.bsky.feed.post", "random" => true}),
    do: "Post content generated at emit time"

  defp event_details(%{"type" => "app.bsky.graph.follow"} = row), do: row["subject_did"]
  defp event_details(%{"type" => "app.bsky.feed.post"} = row), do: row["text"]

  defp maybe_subscribe_to_events(socket, events) do
    if connected?(socket) do
      Enum.reduce(events, socket, &subscribe_to_event(&2, &1))
    else
      socket
    end
  end

  defp subscribe_to_event(socket, %{"id" => event_id}) do
    Phoenix.PubSub.subscribe(FirehoseSimulator.PubSub, EventEmitter.topic(event_id))
    socket
  end

  defp replace_event(events, updated_event) do
    Enum.map(events, fn event ->
      if event["id"] == updated_event["id"], do: updated_event, else: event
    end)
  end

  defp assign_event_totals(socket) do
    assign(socket,
      events_count: Enum.sum(Enum.map(socket.assigns.events, & &1["emitted_count"])),
      last_event_at: last_event_at(socket.assigns.events)
    )
  end

  defp last_event_at(events) do
    events
    |> Enum.map(& &1["last_emitted_at"])
    |> Enum.reject(&is_nil/1)
    |> Enum.max(fn -> nil end)
  end
end
