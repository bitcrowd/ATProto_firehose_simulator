defmodule FirehoseSimulator.Data do
  alias Aether.ATProto.CID

  @did_prefix "did:plc:firesim"
  @post_text_prefix "[sim] "
  @post_type "app.bsky.feed.post"
  @follow_type "app.bsky.graph.follow"

  def did_prefix, do: @did_prefix
  def post_text_prefix, do: @post_text_prefix
  def post_type, do: @post_type
  def follow_type, do: @follow_type

  def simulator_did?(value) when is_binary(value), do: String.starts_with?(value, @did_prefix)
  def simulator_did?(_value), do: false

  def simulator_post_text?(value) when is_binary(value),
    do: String.starts_with?(value, @post_text_prefix)

  def simulator_post_text?(_value), do: false

  def mark_post_text(text) when is_binary(text) do
    if simulator_post_text?(text), do: text, else: @post_text_prefix <> text
  end

  def cleanup_notice do
    "Cleanup connects to Postgres and only deletes rows that match registered simulator markers such as did:plc:firesim:. Unknown or ambiguous data is skipped."
  end

  def cleanup_rules do
    [
      %{
        id: :did_owner,
        description: "Delete rows whose owning DID is simulator-owned.",
        priority: 20,
        columns: ["did", "author_did"],
        match: {:prefix, @did_prefix}
      },
      %{
        id: :repo_owner,
        description: "Delete rows whose owning repo DID is simulator-owned.",
        priority: 10,
        columns: ["repo"],
        match: {:prefix, @did_prefix}
      }
    ]
  end

  def create_record(@follow_type = type, opts) do
    subject = Keyword.fetch!(opts, :subject)
    created_at = Keyword.get(opts, :created_at, DateTime.utc_now() |> DateTime.to_iso8601())

    %{
      "$type" => type,
      "subject" => subject,
      "createdAt" => created_at
    }
  end

  def create_record(@post_type = type, opts) do
    text = Keyword.fetch!(opts, :text)
    created_at = Keyword.get(opts, :created_at, DateTime.utc_now() |> DateTime.to_iso8601())

    %{
      "$type" => type,
      "text" => text,
      "langs" => ["en"],
      "createdAt" => created_at
    }
  end

  def did_for_user_id(user_id) when is_integer(user_id) do
    "did:plc:firesim#{user_id}"
  end

  def random_did(excluded \\ nil) do
    did = System.unique_integer([:positive]) |> did_for_user_id()

    if did == excluded, do: random_did(excluded), else: did
  end

  def cid_for_record(record) when is_map(record) do
    record
    |> Jason.encode!()
    |> CID.from_data()
    |> Aether.ATProto.CID.cid_to_string()
  end
end
