defmodule FirehoseSimulator.DataTest do
  use ExUnit.Case, async: true

  alias FirehoseSimulator.Data

  test "builds a synthetic did from a user id" do
    assert Data.did_for_user_id(123) == "did:plc:firesim123"
  end

  test "builds a post record via the shared data module" do
    assert Data.create_record(Data.post_type(), text: "hello", created_at: "2025-01-01T00:00:00Z") ==
             %{
               "$type" => "app.bsky.feed.post",
               "text" => "hello",
               "langs" => ["en"],
               "createdAt" => "2025-01-01T00:00:00Z"
             }
  end

  test "generates synthetic random dids in the sim namespace" do
    did = Data.random_did()

    assert String.starts_with?(did, "did:plc:firesim")
  end
end
