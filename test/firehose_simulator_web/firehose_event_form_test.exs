defmodule FirehoseSimulatorWeb.FirehoseEventFormTest do
  use ExUnit.Case, async: true

  alias FirehoseSimulatorWeb.FirehoseEventForm

  test "validates a manual follow event" do
    assert {:ok, event_attrs} =
             FirehoseEventForm.validate(%{
               "type" => "app.bsky.graph.follow",
               "random" => "false",
               "time_ms" => "1000",
               "author_did" => "did:plc:firesimauthor123",
               "subject_did" => "did:plc:firesimsubject123"
             })

    assert event_attrs["type"] == "app.bsky.graph.follow"
    assert event_attrs["text"] == nil
    assert event_attrs["time_ms"] == 1000
    assert event_attrs["emitted_count"] == 0
  end

  test "validates a manual post event" do
    assert {:ok, event_attrs} =
             FirehoseEventForm.validate(%{
               "type" => "app.bsky.feed.post",
               "random" => "false",
               "time_ms" => "250",
               "author_did" => "did:plc:firesimauthor123",
               "text" => "hello world"
             })

    assert event_attrs["type"] == "app.bsky.feed.post"
    assert event_attrs["subject_did"] == nil
    assert event_attrs["time_ms"] == 250
    assert event_attrs["emitted_count"] == 0
  end

  test "rejects unsupported event types" do
    assert {:error, changeset} =
             FirehoseEventForm.validate(%{"type" => "profile.update", "random" => "true"})

    assert errors_on(changeset) == %{type: ["Choose a supported event type"]}
  end

  test "rejects invalid dids" do
    assert {:error, changeset} =
             FirehoseEventForm.validate(%{
               "type" => "app.bsky.feed.post",
               "random" => "false",
               "time_ms" => "1000",
               "author_did" => "not-a-did",
               "text" => "hello"
             })

    assert errors_on(changeset) == %{author_did: ["DID must start with did:"]}
  end

  test "accepts non-simulator dids for manual input" do
    assert {:ok, event_attrs} =
             FirehoseEventForm.validate(%{
               "type" => "app.bsky.feed.post",
               "random" => "false",
               "time_ms" => "1000",
               "author_did" => "did:plc:author123",
               "text" => "hello"
             })

    assert event_attrs["author_did"] == "did:plc:author123"
  end

  test "defaults missing emit frequency to 1000ms" do
    assert {:ok, event_attrs} =
             FirehoseEventForm.validate(%{
               "type" => "app.bsky.feed.post",
               "random" => "true"
             })

    assert event_attrs["time_ms"] == 1000
  end

  test "rejects non-positive emit frequency" do
    assert {:error, changeset} =
             FirehoseEventForm.validate(%{
               "type" => "app.bsky.feed.post",
               "random" => "true",
               "time_ms" => "0"
             })

    assert errors_on(changeset) == %{time_ms: ["Emit frequency must be greater than 0 ms"]}
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)
  end
end
