defmodule FirehoseSimulator.BaseData.UserbaseExport do
  alias FirehoseSimulator.BaseData.FollowerGraph
  alias FirehoseSimulator.BaseData.Userbase
  alias FirehoseSimulator.BaseData.UserbaseMeta
  alias FirehoseSimulator.BulkCreation

  @spec export(Userbase.t(), String.t(), keyword()) :: {:ok, map()} | {:error, String.t()}
  def export(%Userbase{} = userbase, export_root, opts \\ [])
      when is_binary(export_root) and is_list(opts) do
    run_id = Keyword.get_lazy(opts, :run_id, fn -> default_run_id(userbase.name) end)
    export_root = Path.expand(export_root)
    run_dir = Path.join(export_root, run_id)
    actor_csv_path = Path.join(run_dir, "actor.csv")
    follow_csv_path = Path.join(run_dir, "follow.csv")
    meta_path = Path.join(run_dir, "userbase_meta.json")

    with {:ok, export_data} <-
           export_content(
             userbase,
             Keyword.merge(
               opts,
               actor_csv_path: actor_csv_path,
               follow_csv_path: follow_csv_path
             )
           ),
         {:ok, actor_count} <- write_actor_csv(actor_csv_path, export_data.actor_rows),
         {:ok, follow_count} <- write_follow_csv(follow_csv_path, export_data.follow_rows),
         :ok <- File.write(meta_path, export_data.meta_json) do
      {:ok,
       %{
         run_id: export_data.run_id,
         export_dir: run_dir,
         meta_path: meta_path,
         actor_csv_path: actor_csv_path,
         follow_csv_path: follow_csv_path,
         actor_row_count: actor_count,
         follow_row_count: follow_count,
         first_user_id: 1,
         last_user_id: userbase.num_users
       }}
    else
      {:error, reason} ->
        {:error, "#{reason} (run_dir=#{run_dir})"}
    end
  end

  @spec export_content(Userbase.t(), keyword()) :: {:ok, map()} | {:error, String.t()}
  def export_content(%Userbase{} = userbase, opts \\ []) when is_list(opts) do
    run_id = Keyword.get_lazy(opts, :run_id, fn -> default_run_id(userbase.name) end)
    indexed_at = Keyword.get_lazy(opts, :indexed_at, &current_indexed_at/0)
    base_time = Keyword.get_lazy(opts, :base_time, &current_base_time/0)
    actor_csv_path = Keyword.get(opts, :actor_csv_path, "/tmp/actor.csv")
    follow_csv_path = Keyword.get(opts, :follow_csv_path, "/tmp/follow.csv")

    with actor_rows <- actor_rows(userbase, indexed_at),
         {:ok, follow_rows} <- follow_rows(userbase, base_time),
         actor_csv <- actor_rows_to_csv(actor_rows),
         follow_csv <- follow_rows_to_csv(follow_rows),
         meta <-
           build_meta(
             userbase,
             run_id,
             actor_csv_path,
             length(actor_rows),
             follow_csv_path,
             length(follow_rows)
           ),
         {:ok, meta_json} <- UserbaseMeta.encode(meta) do
      {:ok,
       %{
         run_id: run_id,
         actor_rows: actor_rows,
         follow_rows: follow_rows,
         actor_csv: actor_csv,
         follow_csv: follow_csv,
         actor_row_count: length(actor_rows),
         follow_row_count: length(follow_rows),
         meta: meta,
         meta_json: meta_json
       }}
    end
  end

  @spec actor_rows(Userbase.t(), String.t()) :: [map()]
  def actor_rows(%Userbase{} = userbase, indexed_at) when is_binary(indexed_at) do
    Enum.map(1..userbase.num_users, &BulkCreation.actor_row(&1, indexed_at))
  end

  @spec follow_rows(Userbase.t(), DateTime.t()) :: {:ok, [map()]} | {:error, String.t()}
  def follow_rows(%Userbase{} = userbase, %DateTime{} = base_time) do
    with {:ok, graph, _follows_count} <-
           FollowerGraph.generate(userbase.num_users, follower_density: userbase.follower_density) do
      {:ok,
       graph
       |> Enum.sort_by(fn {user_id, _followers} -> user_id end)
       |> Enum.with_index()
       |> Enum.flat_map(fn {{subject_id, follower_ids}, subject_offset} ->
         Enum.with_index(follower_ids, 1)
         |> Enum.map(fn {actor_id, follower_offset} ->
           BulkCreation.follow_row(
             actor_id,
             subject_id,
             base_time,
             (subject_offset + follower_offset - 1) * 10
           )
         end)
       end)}
    end
  end

  defp build_meta(userbase, run_id, actor_path, actor_count, follow_path, follow_count) do
    UserbaseMeta.new(
      run_id: run_id,
      exported_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      userbase: %{
        "name" => userbase.name,
        "num_users" => userbase.num_users,
        "max_active_user_id" => userbase.max_active_user_id,
        "follower_density" => userbase.follower_density
      },
      files: %{
        actor: %{path: actor_path, row_count: actor_count},
        follow: %{path: follow_path, row_count: follow_count}
      }
    )
  end

  defp write_actor_csv(path, actor_rows) when is_list(actor_rows) do
    with {:ok, device} <- open_file(path) do
      try do
        actor_rows
        |> Enum.reduce(0, fn row, count ->
          row
          |> actor_csv_row()
          |> write_line(device)

          count + 1
        end)
        |> then(&{:ok, &1})
      rescue
        error in File.Error -> {:error, Exception.message(error)}
      after
        File.close(device)
      end
    end
  end

  @spec actor_rows_to_csv([map()]) :: String.t()
  def actor_rows_to_csv(actor_rows) when is_list(actor_rows) do
    Enum.map_join(actor_rows, "", fn row ->
      row
      |> actor_csv_row()
    end)
  end

  @spec follow_rows_to_csv([map()]) :: String.t()
  def follow_rows_to_csv(follow_rows) when is_list(follow_rows) do
    Enum.map_join(follow_rows, "", fn row ->
      row
      |> follow_csv_row()
    end)
  end

  defp write_follow_csv(path, follow_rows) when is_list(follow_rows) do
    with {:ok, device} <- open_file(path) do
      try do
        follow_rows
        |> Enum.reduce(0, fn row, count ->
          row
          |> follow_csv_row()
          |> write_line(device)

          count + 1
        end)
        |> then(&{:ok, &1})
      rescue
        error in File.Error -> {:error, Exception.message(error)}
      after
        File.close(device)
      end
    end
  end

  defp actor_csv_row(row) do
    csv_row([row.did, row.indexedAt, to_string(row.trustedVerifier)])
  end

  defp follow_csv_row(row) do
    csv_row([row.uri, row.cid, row.creator, row.subjectDid, row.createdAt, row.indexedAt])
  end

  defp csv_row(values) do
    escaped =
      Enum.map_join(values, ",", fn value ->
        value
        |> to_string()
        |> String.replace("\"", "\"\"")
        |> then(&"\"#{&1}\"")
      end)

    escaped <> "\n"
  end

  defp write_line(line, device) do
    :ok = IO.binwrite(device, line)
    line
  end

  defp open_file(path) do
    case File.open(path, [:write, :utf8]) do
      {:ok, device} -> {:ok, device}
      {:error, reason} -> {:error, "failed to open csv file #{path}: #{inspect(reason)}"}
    end
  end

  defp current_indexed_at do
    DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  end

  defp current_base_time do
    DateTime.utc_now() |> DateTime.truncate(:microsecond)
  end

  defp default_run_id(name) do
    slug =
      name
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/u, "-")
      |> String.trim("-")
      |> case do
        "" -> "userbase"
        value -> value
      end

    timestamp =
      DateTime.utc_now()
      |> DateTime.truncate(:second)
      |> DateTime.to_iso8601(:basic)
      |> String.replace(":", "")

    "#{slug}-#{timestamp}"
  end
end
