defmodule FirehoseSimulator.Player.Event do
  alias Aether.ATProto.TID
  alias FirehoseSimulator.Data

  @clock_id 0

  def from_config(config) when is_map(config) do
    {did, record} = build_record(config)

    {cid_link, ops} = cid_link_and_ops(record)

    commit_event(did, cid_link, ops, record)
  end

  defp build_record(%{"type" => "app.bsky.graph.follow", "random" => true}) do
    author_did = Data.random_did()
    subject_did = Data.random_did(author_did)

    {author_did, Data.create_record("app.bsky.graph.follow", subject: subject_did)}
  end

  defp build_record(%{
         "type" => "app.bsky.graph.follow",
         "author_did" => author_did,
         "subject_did" => subject_did
       }) do
    {author_did, Data.create_record("app.bsky.graph.follow", subject: subject_did)}
  end

  defp build_record(%{"type" => "app.bsky.feed.post", "random" => true}) do
    author_did = Data.random_did()
    text = random_post_text()

    {author_did, Data.create_record("app.bsky.feed.post", text: text)}
  end

  defp build_record(%{"type" => "app.bsky.feed.post", "author_did" => author_did, "text" => text}) do
    {author_did, Data.create_record("app.bsky.feed.post", text: text)}
  end

  defp cid_link_and_ops(record) do
    type = Map.fetch!(record, "$type")

    record_bytes = CBOR.encode(record)
    record_cid_string = Aether.ATProto.CID.from_data(record_bytes)

    rkey = TID.new()

    cid_link = cid_link!(record_cid_string)

    ops = [op(type, rkey, cid_link)]

    {cid_link, ops}
  end

  defp op(type, rkey, cid_link) do
    %{
      "action" => "create",
      "path" => "#{type}/#{rkey}",
      "cid" => cid_link
    }
  end

  defp commit(did, cid_link, rev, prev \\ nil) do
    %{
      "version" => 3,
      "did" => did,
      "rev" => rev,
      "data" => cid_link,
      "prev" => prev
    }
  end

  defp commit_event(did, cid_link, ops, record) do
    event_type = "com.atproto.sync.subscribeRepos#commit"
    seq = System.unique_integer([:monotonic, :positive])

    now = DateTime.utc_now()
    timestamp = DateTime.to_unix(now)

    time = DateTime.to_iso8601(now)

    rev = TID.from_timestamp(timestamp, @clock_id)

    # time diff since rev of prev
    since = nil

    record_bytes = CBOR.encode(record)

    record_cid_string = Aether.ATProto.CID.from_data(record_bytes)

    commit_data = commit(did, cid_link, rev)
    commit_bytes = CBOR.encode(commit_data)
    commit_cid_string = Aether.ATProto.CID.from_data(commit_bytes)
    commit_cid_link = cid_link!(commit_cid_string)

    car =
      encode_car!(
        commit_cid_string,
        [
          {commit_cid_string, commit_bytes},
          {record_cid_string, record_bytes}
        ]
      )

    blocks = %CBOR.Tag{tag: :bytes, value: car}

    event = %{
      "$type" => event_type,
      "repo" => did,
      "seq" => seq,
      "time" => time,
      "rev" => rev,
      "since" => since,
      "commit" => commit_cid_link,
      "tooBig" => false,
      "rebase" => false,
      "blocks" => blocks,
      "ops" => ops,
      "blobs" => []
      # "prevData" => nil
    }

    header = %{"op" => 1, "t" => "#commit"} |> CBOR.encode()
    payload = CBOR.encode(event)

    [header, payload]
  end

  defp cid_link!(%Aether.ATProto.CID{} = cid) do
    cid |> Aether.ATProto.CID.cid_to_string() |> cid_link!()
  end

  defp cid_link!(cid_string) when is_binary(cid_string) do
    cid_bytes =
      cid_string
      |> CID.decode_cid!()
      |> CID.encode_buffer!()

    %CBOR.Tag{tag: 42, value: %CBOR.Tag{tag: :bytes, value: <<0>> <> cid_bytes}}
  end

  defp encode_car!(root_cid_string, blocks) do
    header =
      %{
        "version" => 1,
        "roots" => [cid_link!(root_cid_string)]
      }
      |> CBOR.encode()

    encoded_blocks =
      blocks
      |> Enum.map(fn {cid_string, block_bytes} ->
        cid_bytes =
          cid_string
          |> CID.decode_cid!()
          |> CID.encode_buffer!()

        block = cid_bytes <> block_bytes
        Aether.ATProto.Varint.encode(byte_size(block)) <> block
      end)
      |> IO.iodata_to_binary()

    Aether.ATProto.Varint.encode(byte_size(header)) <> header <> encoded_blocks
  end

  defp random_post_text() do
    suffix = System.unique_integer([:positive])
    "Simulated post #{suffix}"
  end
end
