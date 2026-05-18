defmodule FirehoseSimulator.Player.Event do
  alias Atex.TID
  alias DASL.{CID, DRISL}
  alias Varint.LEB128
  alias FirehoseSimulator.Data

  @clock_id 0

  def from_config(config) when is_map(config) do
    {did, record} = build_record(config)

    ops = ops(record)

    commit_event(did, ops, record)
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

  defp ops(record) do
    type = Map.fetch!(record, "$type")

    record_bytes = encode_drisl!(record)
    record_cid = CID.compute(record_bytes, :drisl)

    rkey = TID.now() |> TID.encode()

    ops = [op(type, rkey, record_cid)]

    ops
  end

  defp op(type, rkey, record_cid) do
    %{
      "action" => "create",
      "path" => "#{type}/#{rkey}",
      "cid" => record_cid
    }
  end

  defp commit(did, record_cid, rev, prev \\ nil) do
    %{
      "version" => 3,
      "did" => did,
      "rev" => rev,
      "data" => record_cid,
      "prev" => prev
    }
  end

  defp commit_event(did, ops, record) do
    event_type = "com.atproto.sync.subscribeRepos#commit"
    seq = System.unique_integer([:monotonic, :positive])

    now = DateTime.utc_now()
    time = DateTime.to_iso8601(now)

    rev = TID.new(now, @clock_id) |> TID.encode()

    # time diff since rev of prev
    since = nil

    record_bytes = encode_drisl!(record)
    record_cid = CID.compute(record_bytes, :drisl)

    commit_data = commit(did, record_cid, rev)
    commit_bytes = encode_drisl!(commit_data)
    commit_cid = CID.compute(commit_bytes, :drisl)

    car =
      encode_car!(
        commit_cid,
        [
          {commit_cid, commit_bytes},
          {record_cid, record_bytes}
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
      "commit" => commit_cid,
      "tooBig" => false,
      "rebase" => false,
      "blocks" => blocks,
      "ops" => ops,
      "blobs" => []
      # "prevData" => nil
    }

    header = encode_drisl!(%{"op" => 1, "t" => "#commit"})
    payload = encode_drisl!(event)

    [header, payload]
  end

  defp encode_car!(root_cid, blocks) do
    header =
      encode_drisl!(%{
        "version" => 1,
        "roots" => [root_cid]
      })

    encoded_blocks =
      blocks
      |> Enum.map(fn {%CID{bytes: cid_bytes}, block_bytes} ->
        block = cid_bytes <> block_bytes
        LEB128.encode(byte_size(block)) <> block
      end)
      |> IO.iodata_to_binary()

    LEB128.encode(byte_size(header)) <> header <> encoded_blocks
  end

  defp encode_drisl!(term) do
    case DRISL.encode(term) do
      {:ok, bytes} -> bytes
      {:error, reason} -> raise ArgumentError, "failed to DRISL-encode term: #{inspect(reason)}"
    end
  end

  defp random_post_text() do
    suffix = System.unique_integer([:positive])
    "Simulated post #{suffix}"
  end
end
