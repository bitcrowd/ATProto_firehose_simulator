defmodule FirehoseSimulator.EventTest do
  use ExUnit.Case, async: true

  alias FirehoseSimulator.Data
  alias FirehoseSimulator.Event

  test "builds a manual follow event" do
    event =
      Event.from_config(%{
        "type" => "app.bsky.graph.follow",
        "random" => false,
        "author_did" => "did:plc:firesimauthor123",
        "subject_did" => "did:plc:firesimsubject123"
      })

    assert match?([_, _], event)
  end

  test "builds a manual post event" do
    event =
      Event.from_config(%{
        "type" => "app.bsky.feed.post",
        "random" => false,
        "author_did" => "did:plc:firesimauthor123",
        "text" => "hello world"
      })

    assert match?([_, _], event)
  end

  test "builds a random follow event" do
    event = Event.from_config(%{"type" => "app.bsky.graph.follow", "random" => true})

    assert match?([_, _], event)
    payload = decode_payload(event)
    assert String.starts_with?(payload["repo"], Data.did_prefix())
  end

  test "builds a random post event" do
    event = Event.from_config(%{"type" => "app.bsky.feed.post", "random" => true})

    assert match?([_, _], event)
    payload = decode_payload(event)
    assert String.starts_with?(payload["repo"], Data.did_prefix())
  end

  defp decode_payload([_header, payload]) do
    {:ok, decoded, ""} = CBOR.decode(payload)
    decoded
  end
end
