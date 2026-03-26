defmodule FirehoseSimulator.Data do
  alias Aether.ATProto.CID

  @post_type "app.bsky.feed.post"
  @follow_type "app.bsky.graph.follow"

  def post_type, do: @post_type
  def follow_type, do: @follow_type

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
    "did:sim:#{user_id}"
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
