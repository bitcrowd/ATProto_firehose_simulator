defmodule FirehoseSimulator.Player.EventTest do
  use ExUnit.Case, async: true

  alias FirehoseSimulator.Player.Event

  test "builds a manual follow event" do
    event =
      Event.from_config(%{
        "type" => "app.bsky.graph.follow",
        "random" => false,
        "author_did" => "did:plc:author123",
        "subject_did" => "did:plc:subject123"
      })

    assert match?([_, _], event)
  end

  test "builds a manual post event" do
    event =
      Event.from_config(%{
        "type" => "app.bsky.feed.post",
        "random" => false,
        "author_did" => "did:plc:author123",
        "text" => "hello world"
      })

    assert match?([_, _], event)
  end

  test "builds a random follow event" do
    assert match?(
             [_, _],
             Event.from_config(%{"type" => "app.bsky.graph.follow", "random" => true})
           )
  end

  test "builds a random post event" do
    assert match?([_, _], Event.from_config(%{"type" => "app.bsky.feed.post", "random" => true}))
  end
end
