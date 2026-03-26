defmodule FirehoseSimulator.BulkCreation.Post do
  use Ecto.Schema

  @primary_key {:uri, :string, autogenerate: false}
  @schema_prefix "bsky"

  schema "post" do
    field(:cid, :string)
    field(:creator, :string)
    field(:text, :string)
    field(:replyRoot, :string)
    field(:replyRootCid, :string)
    field(:replyParent, :string)
    field(:replyParentCid, :string)
    field(:createdAt, :string)
    field(:indexedAt, :string)
    field(:sortAt, :string)
    field(:langs, :map)
    field(:invalidReplyRoot, :boolean)
    field(:violatesThreadGate, :boolean)
    field(:tags, :map)
    field(:violatesEmbeddingRules, :boolean)
    field(:hasThreadGate, :boolean)
    field(:hasPostGate, :boolean)
    field(:prev, :string)
    field(:sequence, :integer)
  end
end
