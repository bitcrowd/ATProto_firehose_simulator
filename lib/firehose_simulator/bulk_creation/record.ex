defmodule FirehoseSimulator.BulkCreation.Record do
  use Ecto.Schema

  @primary_key {:uri, :string, autogenerate: false}
  @schema_prefix "bsky"

  schema "record" do
    field(:cid, :string)
    field(:did, :string)
    field(:json, :string)
    field(:indexedAt, :string)
    field(:takedownRef, :string)
    field(:tags, :map)
  end
end
