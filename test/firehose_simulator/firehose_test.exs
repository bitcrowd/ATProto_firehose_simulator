defmodule FirehoseSimulator.FirehoseTest do
  use ExUnit.Case, async: false

  alias FirehoseSimulator.Firehose
  alias FirehoseSimulator.Firehose.EventEmitter
  alias FirehoseSimulatorWeb.FirehoseEventForm

  setup do
    :ok = Firehose.reset()
    Phoenix.PubSub.subscribe(FirehoseSimulator.PubSub, "firehose")

    on_exit(fn -> Firehose.reset() end)
    :ok
  end

  test "events starts with no configured events" do
    assert Firehose.events() == []
  end

  test "adds a manual follow event" do
    {:ok, event_attrs} =
      FirehoseEventForm.validate(%{
        "type" => "app.bsky.graph.follow",
        "random" => "false",
        "time_ms" => "1000",
        "author_did" => "did:plc:firesimauthor123",
        "subject_did" => "did:plc:firesimsubject123"
      })

    assert {:ok, event} = Firehose.add_event(event_attrs)

    assert event["type"] == "app.bsky.graph.follow"
    assert event["time_ms"] == 1000
    assert event["emitted_count"] == 0
    assert event["last_emitted_at"] == nil
    assert event["author_did"] == "did:plc:firesimauthor123"
    assert event["subject_did"] == "did:plc:firesimsubject123"
    assert Firehose.events() == [event]
  end

  test "adds a random event" do
    {:ok, event_attrs} =
      FirehoseEventForm.validate(%{
        "type" => "app.bsky.feed.post",
        "random" => "true",
        "time_ms" => "1000"
      })

    assert {:ok, event} = Firehose.add_event(event_attrs)

    assert event["type"] == "app.bsky.feed.post"
    assert event["random"]
    assert event["time_ms"] == 1000
    assert event["emitted_count"] == 0
    assert event["last_emitted_at"] == nil
    assert Firehose.events() == [event]
  end

  test "reset clears configured events" do
    assert :ok = Firehose.reset()
    assert Firehose.events() == []
  end

  test "remove_event terminates the matching emitter" do
    {:ok, event_attrs} =
      FirehoseEventForm.validate(%{
        "type" => "app.bsky.feed.post",
        "random" => "true",
        "time_ms" => "1000"
      })

    assert {:ok, event} = Firehose.add_event(event_attrs)
    assert :ok = Firehose.remove_event(event["id"])
    assert Firehose.events() == []
    assert {:error, :not_found} = Firehose.remove_event(event["id"])
  end

  test "emitters publish events and track their own counts" do
    {:ok, follow_event} =
      FirehoseEventForm.validate(%{
        "type" => "app.bsky.graph.follow",
        "random" => "false",
        "time_ms" => "20",
        "author_did" => "did:plc:firesimauthor123",
        "subject_did" => "did:plc:firesimsubject123"
      })

    {:ok, follow_event} = Firehose.add_event(follow_event)

    Phoenix.PubSub.subscribe(
      FirehoseSimulator.PubSub,
      EventEmitter.topic(follow_event["id"])
    )

    {:ok, post_event} =
      FirehoseEventForm.validate(%{
        "type" => "app.bsky.feed.post",
        "random" => "false",
        "time_ms" => "35",
        "author_did" => "did:plc:firesimauthor456",
        "text" => "hello world"
      })

    {:ok, post_event} = Firehose.add_event(post_event)

    Phoenix.PubSub.subscribe(
      FirehoseSimulator.PubSub,
      EventEmitter.topic(post_event["id"])
    )

    assert_receive [_, _]
    assert_receive [_, _]
    assert_receive {:firehose_event_updated, %{"id" => follow_id, "emitted_count" => 1}}
    assert_receive {:firehose_event_updated, %{"id" => post_id, "emitted_count" => 1}}

    events = Firehose.events()
    assert Enum.map(events, & &1["id"]) == [follow_id, post_id]
    assert Enum.map(events, & &1["emitted_count"]) == [1, 1]
    assert Enum.all?(events, &is_binary(&1["last_emitted_at"]))
  end

  test "reset stops future emissions" do
    {:ok, event_attrs} =
      FirehoseEventForm.validate(%{
        "type" => "app.bsky.feed.post",
        "random" => "true",
        "time_ms" => "15"
      })

    assert {:ok, event} = Firehose.add_event(event_attrs)

    Phoenix.PubSub.subscribe(
      FirehoseSimulator.PubSub,
      EventEmitter.topic(event["id"])
    )

    assert_receive [_, _]
    assert_receive {:firehose_event_updated, %{"id" => id, "emitted_count" => 1}}
    assert :ok = Firehose.reset()
    refute_receive [_, _], 50
    refute_receive {:firehose_event_updated, %{"id" => ^id}}, 50
    assert Firehose.events() == []
  end
end
