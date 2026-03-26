defmodule FirehoseSimulator.BulkCreation.Actor do
  use Ecto.Schema

  @primary_key {:did, :string, autogenerate: false}
  @schema_prefix "bsky"

  schema "actor" do
    field(:indexedAt, :string)
    field(:trustedVerifier, :boolean)
  end
end
