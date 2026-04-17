defmodule FirehoseSimulator.BaseData.UserbaseImportTest do
  use ExUnit.Case, async: false

  alias FirehoseSimulator.BaseData.UserbaseImport

  test "imports from manifest json using the provided copy function" do
    actor_path = "/tmp/actor.csv"
    follow_path = "/tmp/follow.csv"

    meta_json = """
    {
      "version": 1,
      "kind": "userbase",
      "run_id": "import-run",
      "exported_at": "2025-01-01T00:00:00Z",
      "userbase": {
        "name": "demo",
        "num_users": 1,
        "max_active_user_id": 1,
        "follower_density": 1.0
      },
      "files": {
        "actor": {"path": "#{actor_path}", "row_count": 1},
        "follow": {"path": "#{follow_path}", "row_count": 1}
      }
    }
    """

    copy_fun = fn _repo, meta ->
      send(self(), {:copied_meta, meta})
      {:ok, :copied}
    end

    assert {:ok, result} =
             UserbaseImport.import_from_meta_json(
               meta_json,
               __MODULE__.RepoStub,
               validate_files: false,
               copy_fun: copy_fun
             )

    assert result.inserted_actor_count == 1
    assert result.inserted_follow_count == 1

    assert_receive {:copied_meta, meta}
    assert meta.files.actor.path == actor_path
    assert meta.files.follow.path == follow_path
  end

  test "builds copy sql with escaped file paths" do
    sql = UserbaseImport.copy_actor_sql("/tmp/actor's.csv")
    assert sql =~ "COPY bsky.actor"
    assert sql =~ "/tmp/actor''s.csv"
  end

  defmodule RepoStub do
  end
end
