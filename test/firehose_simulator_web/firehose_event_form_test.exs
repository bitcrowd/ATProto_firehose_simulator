defmodule FirehoseSimulatorWeb.FirehoseEventFormTest do
  use ExUnit.Case, async: true

  alias FirehoseSimulatorWeb.FirehoseEventForm

  test "validates a manual follow event" do
    assert {:ok, event_attrs} =
             FirehoseEventForm.validate(%{
               "type" => "app.bsky.graph.follow",
               "random" => "false",
               "author_did" => "did:plc:author123",
               "subject_did" => "did:plc:subject123"
             })

    assert event_attrs["type"] == "app.bsky.graph.follow"
    assert event_attrs["text"] == nil
    assert event_attrs["emitted_count"] == 0
  end

  test "validates a manual post event" do
    assert {:ok, event_attrs} =
             FirehoseEventForm.validate(%{
               "type" => "app.bsky.feed.post",
               "random" => "false",
               "author_did" => "did:plc:author123",
               "text" => "hello world"
             })

    assert event_attrs["type"] == "app.bsky.feed.post"
    assert event_attrs["subject_did"] == nil
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
               "author_did" => "not-a-did",
               "text" => "hello"
             })

    assert errors_on(changeset) == %{author_did: ["DID must start with did:"]}
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)
  end
end
