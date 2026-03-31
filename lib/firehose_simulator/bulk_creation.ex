defmodule FirehoseSimulator.BulkCreation do
  alias FirehoseSimulator.BulkCreation.Actor
  alias FirehoseSimulator.BulkCreation.DynamicRepo
  alias FirehoseSimulator.BulkCreation.Follow
  alias FirehoseSimulator.BulkCreation.Post
  alias FirehoseSimulator.BulkCreation.State
  alias FirehoseSimulator.Data
  alias FirehoseSimulator.DatabaseConnection
  alias FirehoseSimulator.FollowerGraph
  alias FirehoseSimulator.PostAuthorList
  alias FirehoseSimulator.Userbase

  @insert_batch_size 1_000

  def connect(connection_string), do: State.connect(connection_string)
  def current_state, do: State.current_state()
  def reset, do: State.reset()

  def create_posts(count) when is_integer(count) do
    with :ok <- validate_count(count),
         {:ok, repo_name} <- current_repo_name(),
         {:ok, inserted_count, max_user_id, max_post_sequence} <- insert_posts(repo_name, count),
         {:ok, _state} <- State.sync_ids(max_user_id, max_post_sequence) do
      {:ok,
       %{
         inserted_count: inserted_count,
         last_user_id: max_user_id,
         last_post_sequence: max_post_sequence
       }}
    end
  end

  def create_follows(count) when is_integer(count) do
    with :ok <- validate_count(count),
         {:ok, repo_name} <- current_repo_name(),
         {:ok, inserted_count, max_user_id} <- insert_follows(repo_name, count),
         {:ok, _state} <- State.sync_ids(max_user_id, 0) do
      {:ok, %{inserted_count: inserted_count, last_user_id: max_user_id}}
    end
  end

  def create_userbase(%Userbase{} = userbase, %DatabaseConnection{
        connection_string: connection_string
      }) do
    with {:ok, _bulk_state} <- connect(connection_string),
         {:ok, reserved} <- State.reserve(:follows, userbase.num_users),
         first_user_id <- reserved.last_user_id - userbase.num_users + 1,
         user_ids = Enum.to_list(first_user_id..reserved.last_user_id),
         {:ok, graph, follows_count} <- FollowerGraph.generate(userbase.num_users, first_user_id),
         {:ok, inserted_follow_count, last_user_id} <-
           insert_userbase_graph(repo_name(connection_string), user_ids, graph),
         {:ok, _state} <- State.sync_ids(last_user_id, 0) do
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

  def ping(repo_name) do
    with_dynamic_repo(repo_name, fn ->
      case DynamicRepo.query("select 1", []) do
        {:ok, _result} -> :ok
        {:error, error} -> {:error, error}
      end
    end)
  end

  defp insert_posts(repo_name, count), do: insert_generated_posts(repo_name, count)

  defp insert_follows(repo_name, count), do: insert_generated_follows(repo_name, count)

  defp insert_generated_posts(repo_name, count) do
    with {:ok, reserved} <- State.reserve(:posts, count) do
      first_user_id = reserved.last_user_id - count + 1
      first_sequence = reserved.last_post_sequence - count + 1

      with {:ok, user_ids} <- PostAuthorList.generate(count, first_user_id) do
        rows =
          user_ids
          |> Enum.with_index()
          |> Enum.map(fn {user_id, index} ->
            %{
              offset_ms: index * 10,
              user_id: user_id,
              sequence: first_sequence + index
            }
          end)

        do_insert_posts(repo_name, rows)
      end
    end
  end

  defp insert_generated_follows(repo_name, count) do
    with {:ok, reserved} <- State.reserve(:follows, count),
         first_user_id <- reserved.last_user_id - count + 1,
         {:ok, graph, _follows_count} <- FollowerGraph.generate(count, first_user_id) do
      do_insert_graph_follows(repo_name, graph)
    end
  end

  defp do_insert_posts(repo_name, rows) do
    with_dynamic_repo(repo_name, fn ->
      insert_post_rows(rows)
      max_user_id = rows |> Enum.map(& &1.user_id) |> Enum.max(fn -> 0 end)
      max_post_sequence = rows |> Enum.map(& &1.sequence) |> Enum.max(fn -> 0 end)
      {:ok, length(rows), max_user_id, max_post_sequence}
    end)
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

  defp do_insert_graph_follows(repo_name, graph) do
    with_dynamic_repo(repo_name, fn ->
      all_user_ids =
        graph
        |> Map.keys()
        |> Enum.sort()

      insert_actor_rows(all_user_ids)

      follow_rows = follow_rows_from_graph(graph)
      insert_follow_rows(follow_rows)

      max_user_id = Enum.max(all_user_ids, fn -> 0 end)
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

  defp insert_post_rows(rows) do
    all_user_ids = rows |> Enum.map(& &1.user_id) |> Enum.uniq()
    insert_actor_rows(all_user_ids)

    base_time = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    post_rows =
      Enum.map(rows, fn %{offset_ms: offset_ms, user_id: user_id, sequence: sequence} ->
        did = Data.did_for_user_id(user_id)
        created_at = shifted_timestamp(base_time, offset_ms)
        text = post_text(sequence, user_id, nil)
        record = Data.create_record(Data.post_type(), text: text, created_at: created_at)

        %{
          uri: at_uri(did, Data.post_type()),
          cid: Data.cid_for_record(record),
          creator: did,
          text: text,
          createdAt: created_at,
          indexedAt: indexed_timestamp(base_time, offset_ms),
          sequence: sequence
        }
      end)

    insert_all_in_batches(Post, post_rows, on_conflict: :nothing, conflict_target: [:uri])
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

  defp current_repo_name do
    case State.current_state() do
      %{connected?: true, connection_string: connection_string} ->
        {:ok, repo_name(connection_string)}

      _ ->
        {:error, "Set a database connection string first"}
    end
  end

  defp validate_count(count) when count > 0, do: :ok
  defp validate_count(_count), do: {:error, "Count must be greater than 0"}

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

  defp post_text(sequence, user_id, nil), do: "Bulk post #{sequence} from user #{user_id}"
  defp post_text(_sequence, _user_id, text), do: text

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
