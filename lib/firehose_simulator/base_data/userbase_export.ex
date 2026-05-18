defmodule FirehoseSimulator.BaseData.UserbaseExport do
  @moduledoc false
  require Logger

  alias FirehoseSimulator.BaseData.FollowerGraph
  alias FirehoseSimulator.BaseData.Userbase
  alias FirehoseSimulator.BaseData.UserbaseMeta
  alias FirehoseSimulator.BulkCreation

  @spec export(Userbase.t(), String.t(), keyword()) :: {:ok, map()} | {:error, String.t()}
  def export(%Userbase{} = userbase, export_root, opts \\ [])
      when is_binary(export_root) and is_list(opts) do
    run_id = Keyword.get_lazy(opts, :run_id, fn -> default_run_id(userbase.name) end)
    indexed_at = Keyword.get_lazy(opts, :indexed_at, &current_indexed_at/0)
    base_time = Keyword.get_lazy(opts, :base_time, &current_base_time/0)
    run_dir = Path.expand(export_root)
    actor_csv_path = Path.join(run_dir, "actor.csv")
    follow_csv_path = Path.join(run_dir, "follow.csv")
    meta_path = Path.join(run_dir, "userbase_meta.json")

    with :ok <- File.mkdir_p(run_dir),
         {:ok, actor_count} <- write_actor_csv_stream(actor_csv_path, userbase, indexed_at),
         {:ok, follow_count} <- write_follow_csv_stream(follow_csv_path, userbase, base_time),
         meta <-
           build_meta(
             userbase,
             run_id,
             actor_csv_path,
             actor_count,
             follow_csv_path,
             follow_count
           ),
         {:ok, meta_json} <- UserbaseMeta.encode(meta),
         :ok <- File.write(meta_path, meta_json) do
      {:ok,
       %{
         run_id: run_id,
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
      {:error, reason} when is_atom(reason) ->
        {:error, "failed to create export directory #{run_dir}: #{inspect(reason)}"}

      {:error, reason} ->
        {:error, "#{reason} (run_dir=#{run_dir})"}
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

  defp write_actor_csv_stream(path, %Userbase{} = userbase, indexed_at)
       when is_binary(indexed_at) do
    with {:ok, device} <- open_file(path) do
      try do
        counter = :counters.new(1, [])

        1..userbase.num_users
        |> Stream.map(&BulkCreation.actor_row(&1, indexed_at))
        |> Stream.each(fn row ->
          row
          |> actor_csv_row()
          |> write_line(device)

          Logger.debug("wrote actor csv row for #{row.did}")
          :counters.add(counter, 1, 1)
        end)
        |> Stream.run()

        {:ok, :counters.get(counter, 1)}
      rescue
        error in File.Error -> {:error, Exception.message(error)}
      after
        File.close(device)
      end
    end
  end

  defp write_follow_csv_stream(path, %Userbase{} = userbase, %DateTime{} = base_time) do
    with {:ok, device} <- open_file(path) do
      try do
        counter = :counters.new(1, [])

        userbase.num_users
        |> FollowerGraph.stream_follow_batches_by_subject(
          follower_density: userbase.follower_density
        )
        |> Stream.each(fn follows ->
          rows =
            Enum.map(follows, fn %{actor_id: actor_id, subject_id: subject_id} = follow ->
              offset_ms = (follow.subject_offset + follow.follower_offset - 1) * 10
              BulkCreation.follow_row(actor_id, subject_id, base_time, offset_ms)
            end)

          rows
          |> Enum.map_join(&follow_csv_row/1)
          |> write_line(device)

          :counters.add(counter, 1, length(rows))

          subject_id = follows |> hd() |> Map.fetch!(:subject_id)

          Logger.debug("wrote #{length(rows)} follow csv rows for subject #{subject_id}")
        end)
        |> Stream.run()

        {:ok, :counters.get(counter, 1)}
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
