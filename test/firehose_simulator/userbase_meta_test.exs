defmodule FirehoseSimulator.BaseData.UserbaseMetaTest do
  use ExUnit.Case, async: false

  alias FirehoseSimulator.BaseData.UserbaseMeta

  @tag :tmp_dir
  test "loads a valid meta file with absolute paths", %{tmp_dir: tmp_dir} do
    actor_path = Path.join(tmp_dir, "actor.csv")
    follow_path = Path.join(tmp_dir, "follow.csv")
    File.write!(actor_path, "\"actor\"\n")
    File.write!(follow_path, "\"follow\"\n")

    meta = valid_meta(actor_path, follow_path)
    meta_path = Path.join(tmp_dir, "userbase_meta.json")
    assert :ok = UserbaseMeta.write_file(meta, meta_path)

    assert {:ok, loaded} = UserbaseMeta.load_file(meta_path)
    assert loaded.run_id == "test-run"
    assert loaded.files.actor.path == actor_path
    assert loaded.files.follow.row_count == 2
  end

  test "rejects relative csv paths" do
    assert {:error, "actor csv path must be absolute"} =
             UserbaseMeta.from_map(%{
               "version" => 1,
               "kind" => "userbase",
               "run_id" => "test-run",
               "exported_at" => "2025-01-01T00:00:00Z",
               "userbase" => %{"name" => "demo"},
               "files" => %{
                 "actor" => %{"path" => "actor.csv", "row_count" => 1},
                 "follow" => %{"path" => "/tmp/follow.csv", "row_count" => 2}
               }
             })
  end

  test "rejects unsupported versions" do
    assert {:error, "unsupported userbase meta version: 2"} =
             UserbaseMeta.from_map(%{
               "version" => 2,
               "kind" => "userbase",
               "run_id" => "test-run",
               "exported_at" => "2025-01-01T00:00:00Z",
               "userbase" => %{"name" => "demo"},
               "files" => %{
                 "actor" => %{"path" => "/tmp/actor.csv", "row_count" => 1},
                 "follow" => %{"path" => "/tmp/follow.csv", "row_count" => 2}
               }
             })
  end

  defp valid_meta(actor_path, follow_path) do
    UserbaseMeta.new(
      run_id: "test-run",
      exported_at: "2025-01-01T00:00:00Z",
      userbase: %{
        "name" => "demo",
        "num_users" => 2,
        "max_active_user_id" => 2,
        "follower_density" => 1.0
      },
      files: %{
        actor: %{path: actor_path, row_count: 2},
        follow: %{path: follow_path, row_count: 2}
      }
    )
  end
end
