defmodule FirehoseSimulator.BaseData.UserbaseExportTest do
  use ExUnit.Case, async: false

  alias FirehoseSimulator.BaseData.Userbase
  alias FirehoseSimulator.BaseData.UserbaseExport
  alias FirehoseSimulator.BaseData.UserbaseMeta

  test "exports actor and follow csv content with a manifest" do
    userbase = %Userbase{
      name: "Demo Export",
      num_users: 4,
      max_active_user_id: 4,
      follower_density: 1.0
    }

    indexed_at = "2025-01-01T00:00:00Z"
    base_time = DateTime.from_naive!(~N[2025-01-01 00:00:00.000000], "Etc/UTC")

    assert {:ok, result} =
             UserbaseExport.export_content(userbase,
               run_id: "demo-run",
               indexed_at: indexed_at,
               base_time: base_time,
               actor_csv_path: "/tmp/actor.csv",
               follow_csv_path: "/tmp/follow.csv"
             )

    assert result.actor_row_count == 4
    assert result.follow_row_count == 4
    assert 4 == count_lines(result.actor_csv)
    assert 4 == count_lines(result.follow_csv)

    assert {:ok, meta} = UserbaseMeta.load(result.meta_json, validate_files: false)
    assert meta.files.actor.row_count == 4
    assert meta.files.follow.row_count == 4
  end

  test "builds follow rows using the same follower count semantics" do
    userbase = %Userbase{
      name: "Demo Export",
      num_users: 5,
      max_active_user_id: 5,
      follower_density: 1.0
    }

    base_time = DateTime.from_naive!(~N[2025-01-01 00:00:00.000000], "Etc/UTC")

    assert {:ok, follow_rows} = UserbaseExport.follow_rows(userbase, base_time)
    assert length(follow_rows) == 7
  end

  defp count_lines(content) do
    content
    |> String.split("\n", trim: true)
    |> length()
  end
end
