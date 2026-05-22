defmodule FirehoseSimulator.BaseData.UserbaseMetaTest do
  use ExUnit.Case, async: false

  alias FirehoseSimulator.BaseData.UserbaseMeta

  test "loads valid meta json with absolute paths" do
    actor_path = "/tmp/actor.csv"
    follow_path = "/tmp/follow.csv"

    meta_json = """
    {
      "version": 1,
      "kind": "userbase",
      "run_id": "test-run",
      "exported_at": "2025-01-01T00:00:00Z",
      "userbase": {
        "name": "demo",
        "num_users": 2,
        "follower_density": 1.0
      },
      "files": {
        "actor": {"path": "#{actor_path}", "row_count": 2},
        "follow": {"path": "#{follow_path}", "row_count": 2}
      }
    }
    """

    assert {:ok, loaded} = UserbaseMeta.load(meta_json, validate_files: false)
    assert loaded.run_id == "test-run"
    assert loaded.files.actor.path == actor_path
    assert loaded.files.follow.row_count == 2
  end

  test "encodes meta json" do
    meta =
      UserbaseMeta.new(
        run_id: "test-run",
        exported_at: "2025-01-01T00:00:00Z",
        userbase: %{
          "name" => "demo",
          "num_users" => 2,
          "follower_density" => 1.0
        },
        files: %{
          actor: %{path: "/tmp/actor.csv", row_count: 2},
          follow: %{path: "/tmp/follow.csv", row_count: 2}
        }
      )

    assert {:ok, json} = UserbaseMeta.encode(meta)
    assert {:ok, loaded} = UserbaseMeta.load(json, validate_files: false)
    assert loaded == meta
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
end
