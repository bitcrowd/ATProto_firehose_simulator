defmodule FirehoseSimulator.BulkCreationTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias FirehoseSimulator.BulkCreation
  alias FirehoseSimulator.BulkCreation.Vacuum
  alias FirehoseSimulator.DatabaseConnection
  alias FirehoseSimulator.Scenario
  alias FirehoseSimulator.BaseData.Userbase

  test "create_userbase/2 returns the existing connection validation error" do
    userbase = %Userbase{
      name: "not yet twitter",
      num_users: 5,
      max_active_user_id: 5,
      follower_density: 0.0
    }

    connection = %DatabaseConnection{connection_string: "not-a-url"}

    assert {:error, "Connection string must be a postgres URL"} =
             BulkCreation.create_userbase(userbase, connection)
  end

  test "create_userbase/2 surfaces connection failures for unreachable databases" do
    userbase = %Userbase{
      name: "offline import",
      num_users: 3,
      max_active_user_id: 3,
      follower_density: 5.0
    }

    connection =
      %DatabaseConnection{
        connection_string: "postgres://postgres:postgres@127.0.0.1:1/firehose_simulator_test"
      }

    capture_log(fn ->
      assert {:error, message} = BulkCreation.create_userbase(userbase, connection)
      assert is_binary(message)
      refute message == ""
    end)
  end

  test "create_scenario/2 returns the existing connection validation error" do
    scenario = %Scenario{posts: nil, sessions: nil, follows: nil}
    connection = %DatabaseConnection{connection_string: "not-a-url"}

    assert {:error, "Connection string must be a postgres URL"} =
             BulkCreation.create_scenario(scenario, connection)
  end

  test "create_scenario/2 surfaces connection failures for unreachable databases" do
    scenario = %Scenario{
      posts: [%{offset_ms: 100, user_id: 1}],
      sessions: [%{offset_ms: 0, user_id: 2, duration_ms: 60_000}],
      follows: [%{offset_ms: 50, actor_id: 1, subject_id: 2}]
    }

    connection =
      %DatabaseConnection{
        connection_string: "postgres://postgres:postgres@127.0.0.1:1/firehose_simulator_test"
      }

    capture_log(fn ->
      assert {:error, message} = BulkCreation.create_scenario(scenario, connection)
      assert is_binary(message)
      refute message == ""
    end)
  end

  test "vacuum returns action validation errors" do
    assert {:error, "Select at least one vacuum action"} =
             Vacuum.run("postgres://example", [])
  end

  test "vacuum surfaces connection failures for unreachable databases" do
    connection_string = "postgres://postgres:postgres@127.0.0.1:1/firehose_simulator_test"

    capture_log(fn ->
      assert {:error, message} =
               Vacuum.run(connection_string, delete_userbase?: true)

      assert is_binary(message)
      refute message == ""
    end)
  end

  describe "prepare_post_rows/2" do
    test "builds aligned post, record, and feed item rows for each event" do
      base_time = DateTime.from_naive!(~N[2026-04-07 12:00:00.123456], "Etc/UTC")

      events = [
        %{offset_ms: 0, user_id: 7},
        %{offset_ms: 1500, user_id: 9}
      ]

      %{
        post_rows: post_rows,
        record_rows: record_rows,
        feed_item_rows: feed_item_rows
      } = BulkCreation.prepare_post_rows(events, base_time)

      assert length(post_rows) == 2
      assert length(record_rows) == 2
      assert length(feed_item_rows) == 2

      records_by_uri = Map.new(record_rows, &{&1.uri, &1})
      feed_items_by_uri = Map.new(feed_item_rows, &{&1.uri, &1})

      Enum.each(post_rows, fn post_row ->
        assert String.starts_with?(post_row.uri, "at://did:plc:firesim")
        assert post_row.sortAt == post_row.createdAt

        assert %{} = record_row = Map.fetch!(records_by_uri, post_row.uri)
        assert %{} = feed_item_row = Map.fetch!(feed_items_by_uri, post_row.uri)

        assert record_row.cid == post_row.cid
        assert record_row.did == post_row.creator
        assert is_binary(record_row.rev)
        assert record_row.indexedAt == post_row.indexedAt

        assert feed_item_row.cid == post_row.cid
        assert feed_item_row.type == "post"
        assert feed_item_row.postUri == post_row.uri
        assert feed_item_row.originatorDid == post_row.creator
        assert feed_item_row.sortAt == post_row.createdAt

        assert {:ok, record_json} = Jason.decode(record_row.json)
        assert record_json["$type"] == "app.bsky.feed.post"
        assert record_json["createdAt"] == post_row.createdAt
        assert record_json["text"] == post_row.text
        assert record_json["langs"] == ["en"]
      end)
    end
  end
end
