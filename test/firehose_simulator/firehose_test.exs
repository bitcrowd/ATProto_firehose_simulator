defmodule FirehoseSimulator.FirehoseTest do
  use ExUnit.Case, async: false

  alias FirehoseSimulator.Firehose
  alias FirehoseSimulatorWeb.FirehoseEventForm

  setup do
    :ok = Firehose.reset()
    Phoenix.PubSub.subscribe(FirehoseSimulator.PubSub, "firehose")

    on_exit(fn -> Firehose.reset() end)
    :ok
  end

  test "status starts with no configured events" do
    status = Firehose.status()

    assert status.events == []
    assert status.events_count == 0
    assert status.last_event_at == nil
  end

  test "adds a manual follow event" do
    {:ok, event_attrs} =
      FirehoseEventForm.validate(%{
        "type" => "app.bsky.graph.follow",
        "random" => "false",
        "author_did" => "did:plc:author123",
        "subject_did" => "did:plc:subject123"
      })

    assert {:ok, event} =
             Firehose.add_event(event_attrs)

    assert event["type"] == "app.bsky.graph.follow"
    assert event["emitted_count"] == 0
    assert event["author_did"] == "did:plc:author123"
    assert event["subject_did"] == "did:plc:subject123"
    assert Firehose.status().events == [event]
  end

  test "adds a random event" do
    {:ok, event_attrs} =
      FirehoseEventForm.validate(%{
        "type" => "app.bsky.feed.post",
        "random" => "true"
      })

    assert {:ok, event} =
             Firehose.add_event(event_attrs)

    assert event["type"] == "app.bsky.feed.post"
    assert event["random"]
    assert event["emitted_count"] == 0
    assert Firehose.status().events == [event]
  end

  test "tick with no configured rows does not publish or increment counters" do
    send(Firehose, :event)
    _state = :sys.get_state(Firehose)

    refute_receive _

    status = Firehose.status()
    assert status.events_count == 0
    assert status.last_event_at == nil
  end

  test "tick publishes every configured row and increments counters" do
    {:ok, follow_event} =
      FirehoseEventForm.validate(%{
        "type" => "app.bsky.graph.follow",
        "random" => "false",
        "author_did" => "did:plc:author123",
        "subject_did" => "did:plc:subject123"
      })

    {:ok, _} =
      Firehose.add_event(follow_event)

    {:ok, post_event} =
      FirehoseEventForm.validate(%{
        "type" => "app.bsky.feed.post",
        "random" => "false",
        "author_did" => "did:plc:author456",
        "text" => "hello world"
      })

    {:ok, _} =
      Firehose.add_event(post_event)

    send(Firehose, :event)
    _state = :sys.get_state(Firehose)

    assert_receive [_, _]
    assert_receive [_, _]

    status = Firehose.status()
    assert status.events_count == 2
    assert is_binary(status.last_event_at)
    assert Enum.map(status.events, & &1["emitted_count"]) == [1, 1]
  end
end
