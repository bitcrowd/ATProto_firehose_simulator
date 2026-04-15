defmodule FirehoseSimulator.BaseData.UserbaseImportTest do
  use ExUnit.Case, async: false

  alias FirehoseSimulator.BaseData.UserbaseImport
  alias FirehoseSimulator.BaseData.UserbaseMeta

  @tag :tmp_dir
  test "imports from manifest using actor copy then follow copy", %{tmp_dir: tmp_dir} do
    actor_path = Path.join(tmp_dir, "actor.csv")
    follow_path = Path.join(tmp_dir, "follow.csv")
    File.write!(actor_path, "\"actor\"\n")
    File.write!(follow_path, "\"follow\"\n")

    meta_path = Path.join(tmp_dir, "userbase_meta.json")

    :ok =
      UserbaseMeta.write_file(
        UserbaseMeta.new(
          run_id: "import-run",
          exported_at: "2025-01-01T00:00:00Z",
          userbase: %{
            "name" => "demo",
            "num_users" => 1,
            "max_active_user_id" => 1,
            "follower_density" => 1.0
          },
          files: %{
            actor: %{path: actor_path, row_count: 1},
            follow: %{path: follow_path, row_count: 1}
          }
        ),
        meta_path
      )

    assert {:ok, result} = UserbaseImport.import(meta_path, __MODULE__.RepoStub)

    assert result.inserted_actor_count == 1
    assert result.inserted_follow_count == 1

    assert_receive {:repo_query, actor_sql}
    assert actor_sql == UserbaseImport.copy_actor_sql(actor_path)

    assert_receive {:repo_query, follow_sql}
    assert follow_sql == UserbaseImport.copy_follow_sql(follow_path)
  end

  test "builds copy sql with escaped file paths" do
    sql = UserbaseImport.copy_actor_sql("/tmp/actor's.csv")
    assert sql =~ "COPY bsky.actor"
    assert sql =~ "/tmp/actor''s.csv"
  end

  defmodule RepoStub do
    def query(sql, [], _opts) do
      send(self(), {:repo_query, sql})
      {:ok, %{num_rows: 1}}
    end
  end
end
