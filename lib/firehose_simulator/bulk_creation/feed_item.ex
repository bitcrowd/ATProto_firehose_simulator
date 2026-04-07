defmodule FirehoseSimulator.BulkCreation.FeedItem do
  use Ecto.Schema

  @primary_key {:uri, :string, autogenerate: false}
  @schema_prefix "bsky"

  schema "feed_item" do
    field(:cid, :string)
    field(:type, :string)
    field(:postUri, :string)
    field(:originatorDid, :string)
    field(:sortAt, :string)
  end
end
