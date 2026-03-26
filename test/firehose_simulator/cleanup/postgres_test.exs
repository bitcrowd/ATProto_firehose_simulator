defmodule FirehoseSimulator.Cleanup.PostgresTest do
  use ExUnit.Case, async: true

  alias FirehoseSimulator.Cleanup.Postgres

  test "compile_rules builds owner-based rules for supported columns" do
    metadata = [
      %{schema: "bsky", table: "record", column: "repo", data_type: "text", udt_name: "text"},
      %{schema: "public", table: "actor", column: "did", data_type: "text", udt_name: "text"},
      %{schema: "public", table: "account", column: "handle", data_type: "text", udt_name: "text"}
    ]

    rules = Postgres.compile_rules(metadata)

    assert Enum.any?(rules, &(&1.id == :repo_owner and &1.table == "record"))
    assert Enum.any?(rules, &(&1.id == :did_owner and &1.table == "actor"))
    refute Enum.any?(rules, &(&1.table == "account"))
  end
end
