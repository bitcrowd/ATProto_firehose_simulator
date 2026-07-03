defmodule FirehoseSimulator.BulkCreationTest do
  use ExUnit.Case, async: false

  alias FirehoseSimulator.BulkCreation
  alias FirehoseSimulator.BulkCreation.Vacuum

  test "vacuum returns action validation errors" do
    assert {:error, "Select at least one vacuum action"} = Vacuum.run([])
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

      assert [_, _] = post_rows
      assert [_, _] = record_rows
      assert [_, _] = feed_item_rows

      records_by_uri = Map.new(record_rows, &{&1.uri, &1})
      feed_items_by_uri = Map.new(feed_item_rows, &{&1.uri, &1})

      Enum.each(post_rows, fn post_row ->
        assert String.starts_with?(post_row.uri, "at://did:plc:firesim")

        assert %{} = record_row = Map.fetch!(records_by_uri, post_row.uri)
        assert %{} = feed_item_row = Map.fetch!(feed_items_by_uri, post_row.uri)

        assert record_row.cid == post_row.cid
        assert record_row.did == post_row.creator
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
