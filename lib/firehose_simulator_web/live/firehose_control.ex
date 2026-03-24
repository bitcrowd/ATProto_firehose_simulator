defmodule FirehoseSimulatorWeb.FirehoseControlLive do
  use FirehoseSimulatorWeb, :live_view

  alias FirehoseSimulator.Firehose

  def mount(_params, _session, socket) do
    if connected?(socket), do: Process.send_after(self(), :refresh_status, 500)

    status = Firehose.status()

    {:ok,
     assign(socket,
       form: did_form(status.did),
       did: status.did,
       events_count: status.events_count,
       last_event_at: status.last_event_at
     )}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="mx-auto w-full max-w-2xl space-y-4">
        <h2 class="text-2xl font-semibold">Firehose Control</h2>

        <.form for={@form} id="firehose-did-form" phx-submit="set_did" class="flex gap-2">
          <.input
            field={@form[:did]}
            type="text"
            placeholder="did:plc:..."
            class="input flex-1"
            label="DID"
          />
          <.button type="submit" class="btn btn-primary self-end">Apply DID</.button>
        </.form>

        <div><strong>Current DID:</strong> {@did}</div>
        <div><strong>Published events:</strong> {@events_count}</div>
        <div><strong>Last event at:</strong> {@last_event_at || "n/a"}</div>
      </section>
    </Layouts.app>
    """
  end

  def handle_event("set_did", %{"firehose" => %{"did" => did}}, socket) do
    did = String.trim(did)

    case Firehose.set_did(did) do
      :ok ->
        status = Firehose.status()

        {:noreply,
         assign(socket,
           form: did_form(did),
           did: status.did,
           events_count: status.events_count,
           last_event_at: status.last_event_at
         )}

      {:error, reason} ->
        {:noreply, socket |> assign(:form, did_form(did)) |> put_flash(:error, reason)}
    end
  end

  def handle_info(:refresh_status, socket) do
    status = Firehose.status()
    Process.send_after(self(), :refresh_status, 500)

    {:noreply,
     assign(socket,
       did: status.did,
       events_count: status.events_count,
       last_event_at: status.last_event_at
     )}
  end

  defp did_form(did) do
    to_form(%{"did" => did}, as: :firehose)
  end
end
