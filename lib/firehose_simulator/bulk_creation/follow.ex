defmodule FirehoseSimulator.BulkCreation.Follow do
  use Ecto.Schema

  @primary_key {:uri, :string, autogenerate: false}
  @schema_prefix "bsky"

  schema "follow" do
    field(:cid, :string)
    field(:creator, :string)
    field(:subjectDid, :string)
    field(:createdAt, :string)
    field(:indexedAt, :string)
    field(:sortAt, :string)
  end
end
