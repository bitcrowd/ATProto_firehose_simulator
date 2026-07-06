defmodule FirehoseSimulator.Repo.Migrations.CreateBskySchema do
  use Ecto.Migration

  def change do
    execute "CREATE SCHEMA IF NOT EXISTS bsky", "DROP SCHEMA IF EXISTS bsky CASCADE"

    create table(:actor, prefix: "bsky", primary_key: false) do
      add :did, :text, primary_key: true
      add :indexedAt, :text
      add :trustedVerifier, :boolean
    end

    create table(:follow, prefix: "bsky", primary_key: false) do
      add :uri, :text, primary_key: true
      add :cid, :text
      add :creator, :text
      add :subjectDid, :text
      add :createdAt, :text
      add :indexedAt, :text
      add :sortAt, :text
    end

    create table(:feed_item, prefix: "bsky", primary_key: false) do
      add :uri, :text, primary_key: true
      add :cid, :text
      add :type, :text
      add :postUri, :text
      add :originatorDid, :text
      add :sortAt, :text
    end

    create table(:record, prefix: "bsky", primary_key: false) do
      add :uri, :text, primary_key: true
      add :cid, :text
      add :did, :text
      add :json, :text
      add :indexedAt, :text
      add :takedownRef, :text
      add :tags, :map
    end

    create table(:post, prefix: "bsky", primary_key: false) do
      add :uri, :text, primary_key: true
      add :cid, :text
      add :creator, :text
      add :text, :text
      add :replyRoot, :text
      add :replyRootCid, :text
      add :replyParent, :text
      add :replyParentCid, :text
      add :createdAt, :text
      add :indexedAt, :text
      add :sortAt, :text
      add :langs, :map
      add :invalidReplyRoot, :boolean
      add :violatesThreadGate, :boolean
      add :tags, :map
      add :violatesEmbeddingRules, :boolean
      add :hasThreadGate, :boolean
      add :hasPostGate, :boolean
      add :prev, :text
      add :sequence, :integer
    end
  end
end
