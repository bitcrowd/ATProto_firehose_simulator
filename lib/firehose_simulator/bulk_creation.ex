defmodule FirehoseSimulator.BulkCreation do
  alias FirehoseSimulator.BulkCreation.Actor
  alias FirehoseSimulator.BulkCreation.DynamicRepo
  alias FirehoseSimulator.BulkCreation.Follow
  alias FirehoseSimulator.Data
  alias FirehoseSimulator.DatabaseConnection
  alias FirehoseSimulator.SimulationPlan.FollowerGraph
  alias FirehoseSimulator.SimulationPlan.Userbase

  @insert_batch_size 1_000

  def create_userbase(%Userbase{} = userbase, %DatabaseConnection{
        connection_string: connection_string
      }) do
    with :ok <- connect(connection_string),
         first_user_id <- 1,
         user_ids = Enum.to_list(first_user_id..(first_user_id + userbase.num_users - 1)),
         {:ok, graph, follows_count} <- FollowerGraph.generate(userbase.num_users, first_user_id),
         {:ok, inserted_follow_count, last_user_id} <-
           insert_userbase_graph(repo_name(connection_string), user_ids, graph) do
      {:ok,
       %{
         inserted_actor_count: length(user_ids),
         inserted_follow_count: inserted_follow_count,
         first_user_id: first_user_id,
         last_user_id: last_user_id,
         follows_count: follows_count
       }}
    end
  end

  def repo_name(connection_string) do
    :"bulk_repo_#{:erlang.phash2(connection_string)}"
  end

  def connect(connection_string) when is_binary(connection_string) do
    with :ok <- validate_connection_string(connection_string),
         {:ok, _pid} <- DynamicRepo.connect(repo_name(connection_string), connection_string) do
      :ok
    end
  end

  defp insert_userbase_graph(repo_name, user_ids, graph) do
    with_dynamic_repo(repo_name, fn ->
      insert_actor_rows(user_ids)

      follow_rows = follow_rows_from_graph(graph)
      insert_follow_rows(follow_rows)

      max_user_id = Enum.max(user_ids, fn -> 0 end)
      {:ok, length(follow_rows), max_user_id}
    end)
  end

  defp follow_rows_from_graph(graph) do
    graph
    |> Enum.sort_by(fn {user_id, _followers} -> user_id end)
    |> Enum.with_index()
    |> Enum.flat_map(fn {{subject_id, follower_ids}, subject_offset} ->
      Enum.with_index(follower_ids, 1)
      |> Enum.map(fn {actor_id, follower_offset} ->
        %{
          offset_ms: (subject_offset + follower_offset - 1) * 10,
          actor_id: actor_id,
          subject_id: subject_id
        }
      end)
    end)
  end

  defp insert_actor_rows(user_ids) do
    indexed_at = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

    actor_rows =
      Enum.map(user_ids, fn user_id ->
        %{
          did: Data.did_for_user_id(user_id),
          indexedAt: indexed_at,
          trustedVerifier: false
        }
      end)

    insert_all_in_batches(Actor, actor_rows, on_conflict: :nothing, conflict_target: [:did])
  end

  defp insert_follow_rows(rows) do
    base_time = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    follow_rows =
      Enum.map(rows, fn %{offset_ms: offset_ms, actor_id: actor_id, subject_id: subject_id} ->
        did = Data.did_for_user_id(actor_id)
        subject_did = Data.did_for_user_id(subject_id)
        created_at = shifted_timestamp(base_time, offset_ms)

        record =
          Data.create_record(Data.follow_type(), subject: subject_did, created_at: created_at)

        %{
          uri: at_uri(did, Data.follow_type()),
          cid: Data.cid_for_record(record),
          creator: did,
          subjectDid: subject_did,
          createdAt: created_at,
          indexedAt: indexed_timestamp(base_time, offset_ms)
        }
      end)

    insert_all_in_batches(Follow, follow_rows, on_conflict: :nothing, conflict_target: [:uri])
  end

  defp validate_connection_string("postgres://" <> _), do: :ok
  defp validate_connection_string("postgresql://" <> _), do: :ok
  defp validate_connection_string(_), do: {:error, "Connection string must be a postgres URL"}

  defp insert_all_in_batches(_schema, [], _opts), do: :ok

  defp insert_all_in_batches(schema, rows, opts) do
    rows
    |> Enum.chunk_every(@insert_batch_size)
    |> Enum.each(fn batch ->
      DynamicRepo.insert_all(schema, batch, opts)
    end)
  end

  defp at_uri(did, collection) do
    "at://#{did}/#{collection}/#{System.unique_integer([:positive, :monotonic])}"
  end

  defp shifted_timestamp(base_time, offset_ms) do
    base_time
    |> DateTime.add(offset_ms, :millisecond)
    |> DateTime.to_iso8601()
  end

  defp indexed_timestamp(base_time, offset_ms) do
    base_time
    |> DateTime.add(offset_ms, :millisecond)
    |> DateTime.truncate(:millisecond)
    |> DateTime.to_iso8601()
  end

  defp with_dynamic_repo(repo_name, fun) do
    previous_repo = DynamicRepo.get_dynamic_repo()
    DynamicRepo.put_dynamic_repo(repo_name)

    try do
      fun.()
    rescue
      error in [DBConnection.ConnectionError, Postgrex.Error] ->
        {:error, Exception.message(error)}
    after
      DynamicRepo.put_dynamic_repo(previous_repo)
    end
  end
end
