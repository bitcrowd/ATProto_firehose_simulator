defmodule FirehoseSimulator.BaseData.UserbaseExportTest do
  use ExUnit.Case, async: false

  alias FirehoseSimulator.BaseData.Userbase
  alias FirehoseSimulator.BaseData.UserbaseExport
  alias FirehoseSimulator.BaseData.UserbaseMeta
  alias FirehoseSimulator.Data

  @moduletag :tmp_dir

  test "exports actor and follow csv files with a manifest", %{tmp_dir: tmp_dir} do
    userbase = %Userbase{
      name: "Demo Export",
      num_users: 4,
      follower_density: 1.0
    }

    indexed_at = "2025-01-01T00:00:00Z"
    base_time = DateTime.from_naive!(~N[2025-01-01 00:00:00.000000], "Etc/UTC")
    export_root = temp_export_root!(tmp_dir)
    run_dir = Path.join(export_root, "demo-run")

    assert {:ok, result} =
             UserbaseExport.export(userbase, export_root,
               run_id: "demo-run",
               indexed_at: indexed_at,
               base_time: base_time
             )

    assert result.export_dir == Path.expand(export_root)
    assert File.regular?(result.actor_csv_path)
    assert File.regular?(result.follow_csv_path)
    assert File.regular?(result.meta_path)
    assert result.actor_row_count == 4
    assert result.follow_row_count == 4
    assert 4 == count_lines(result.actor_csv_path)
    assert 4 == count_lines(result.follow_csv_path)

    assert {:ok, meta} = UserbaseMeta.load_file(result.meta_path, validate_files: true)
    assert meta.files.actor.row_count == 4
    assert meta.files.follow.row_count == 4
    assert result.actor_csv_path == Path.join(Path.expand(export_root), "actor.csv")
    assert result.follow_csv_path == Path.join(Path.expand(export_root), "follow.csv")
    refute File.exists?(run_dir)
  end

  test "actor csv row count matches num_users", %{tmp_dir: tmp_dir} do
    userbase = %Userbase{
      name: "Actor Count Export",
      num_users: 5,
      follower_density: 1.0
    }

    export_root = temp_export_root!(tmp_dir)

    assert {:ok, result} = UserbaseExport.export(userbase, export_root, run_id: "actor-count")
    assert count_lines(result.actor_csv_path) == 5
  end

  test "follow csv row count matches deterministic follower semantics", %{tmp_dir: tmp_dir} do
    userbase = %Userbase{
      name: "Follow Count Export",
      num_users: 5,
      follower_density: 1.0
    }

    export_root = temp_export_root!(tmp_dir)

    assert {:ok, result} = UserbaseExport.export(userbase, export_root, run_id: "follow-count")
    assert count_lines(result.follow_csv_path) == 7
  end

  test "follow csv preserves deterministic subject and follower ordering", %{tmp_dir: tmp_dir} do
    userbase = %Userbase{
      name: "Ordered Follow Export",
      num_users: 4,
      follower_density: 1.0
    }

    export_root = temp_export_root!(tmp_dir)

    assert {:ok, result} = UserbaseExport.export(userbase, export_root, run_id: "follow-order")

    assert read_csv(result.follow_csv_path) |> Enum.map(&follow_edge/1) == [
             {Data.did_for_user_id(2), Data.did_for_user_id(1)},
             {Data.did_for_user_id(3), Data.did_for_user_id(1)},
             {Data.did_for_user_id(4), Data.did_for_user_id(1)},
             {Data.did_for_user_id(3), Data.did_for_user_id(2)}
           ]
  end

  test "export uses the provided timestamps consistently", %{tmp_dir: tmp_dir} do
    userbase = %Userbase{
      name: "Timestamp Export",
      num_users: 4,
      follower_density: 1.0
    }

    indexed_at = "2025-01-01T00:00:00Z"
    base_time = DateTime.from_naive!(~N[2025-01-01 00:00:00.000000], "Etc/UTC")
    export_root = temp_export_root!(tmp_dir)

    assert {:ok, result} =
             UserbaseExport.export(userbase, export_root,
               run_id: "timestamps",
               indexed_at: indexed_at,
               base_time: base_time
             )

    actor_rows = read_csv(result.actor_csv_path)
    follow_rows = read_csv(result.follow_csv_path)

    assert Enum.all?(actor_rows, fn [_did, row_indexed_at, _trusted_verifier] ->
             row_indexed_at == indexed_at
           end)

    assert Enum.map(follow_rows, fn [
                                      _uri,
                                      _cid,
                                      _creator,
                                      _subject_did,
                                      created_at,
                                      row_indexed_at
                                    ] ->
             {created_at, row_indexed_at}
           end) == [
             {"2025-01-01T00:00:00.000000Z", "2025-01-01T00:00:00.000Z"},
             {"2025-01-01T00:00:00.010000Z", "2025-01-01T00:00:00.010Z"},
             {"2025-01-01T00:00:00.020000Z", "2025-01-01T00:00:00.020Z"},
             {"2025-01-01T00:00:00.010000Z", "2025-01-01T00:00:00.010Z"}
           ]
  end

  defp temp_export_root!(tmp_dir) do
    path = Path.join(tmp_dir, "userbase-export-test-#{System.unique_integer([:positive])}")

    File.mkdir_p!(path)
    path
  end

  defp count_lines(path) do
    path
    |> File.read!()
    |> String.split("\n", trim: true)
    |> length()
  end

  defp read_csv(path) do
    path
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.map(&parse_csv_line/1)
  end

  defp follow_edge([_uri, _cid, creator, subject_did, _created_at, _indexed_at]) do
    {creator, subject_did}
  end

  defp parse_csv_line(line) do
    line
    |> String.split("\",\"", trim: true)
    |> Enum.map(fn value ->
      value
      |> String.trim_leading("\"")
      |> String.trim_trailing("\"")
      |> String.replace("\"\"", "\"")
    end)
  end
end
