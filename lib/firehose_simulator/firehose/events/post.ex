defmodule FirehoseSimulator.Firehose.Events.Post do
  use Ecto.Schema

  import Ecto.Changeset

  @event_type "app.bsky.feed.post"

  @primary_key false
  embedded_schema do
    field(:type, :string, default: @event_type)
    field(:random, :boolean, default: true)
    field(:author_did, :string)
    field(:text, :string)
    field(:emitted_count, :integer, default: 0)
  end

  def type, do: @event_type

  def changeset(configured_event, attrs) do
    configured_event
    |> cast(attrs, [:type, :random, :author_did, :text])
    |> validate_required([:type, :random])
    |> validate_inclusion(:type, [@event_type], message: "Choose a supported event type")
    |> normalize_string(:author_did)
    |> normalize_string(:text)
    |> validate_manual_fields()
  end

  def to_event_attrs(changeset) do
    with {:ok, configured_event} <- apply_action(changeset, :insert) do
      {:ok,
       %{
         "id" => System.unique_integer([:positive, :monotonic]),
         "type" => configured_event.type,
         "random" => configured_event.random,
         "emitted_count" => configured_event.emitted_count || 0,
         "author_did" => configured_event.author_did,
         "subject_did" => nil,
         "text" => configured_event.text
       }}
    end
  end

  defp validate_manual_fields(changeset) do
    if get_field(changeset, :random) do
      changeset
    else
      changeset
      |> validate_required([:author_did], message: "Author DID is required")
      |> validate_required([:text], message: "Text is required")
      |> validate_did(:author_did)
    end
  end

  defp validate_did(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      if String.starts_with?(value, "did:") do
        []
      else
        [{field, "DID must start with did:"}]
      end
    end)
  end

  defp normalize_string(changeset, field) do
    update_change(changeset, field, fn value ->
      value
      |> String.trim()
      |> case do
        "" -> nil
        trimmed -> trimmed
      end
    end)
  end
end
