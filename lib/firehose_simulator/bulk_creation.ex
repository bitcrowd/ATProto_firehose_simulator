defmodule FirehoseSimulator.BulkCreation do
  alias FirehoseSimulator.BulkCreation.Actor
  alias FirehoseSimulator.BulkCreation.DynamicRepo
  alias FirehoseSimulator.BulkCreation.FeedItem
  alias FirehoseSimulator.BulkCreation.Follow
  alias FirehoseSimulator.BulkCreation.Post
  alias FirehoseSimulator.BulkCreation.Record
  alias FirehoseSimulator.Data
  alias FirehoseSimulator.DatabaseConnection
  alias FirehoseSimulator.SimulationPlan
  alias FirehoseSimulator.BaseData.FollowerGraph
  alias FirehoseSimulator.BaseData.Userbase
  alias Aether.ATProto.TID

  @insert_batch_size 5_000

  def create_userbase(%Userbase{} = userbase, %DatabaseConnection{
        connection_string: connection_string
      }) do
    with :ok <- connect(connection_string),
         first_user_id <- 1,
         user_ids = Enum.to_list(first_user_id..(first_user_id + userbase.num_users - 1)),
         {:ok, graph, follows_count} <-
           FollowerGraph.generate(userbase.num_users,
             start_id: first_user_id,
             follower_density: userbase.follower_density
           ),
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

  def create_simulation_plan(%SimulationPlan{} = simulation_plan, %DatabaseConnection{
        connection_string: connection_string
      }) do
    with :ok <- connect(connection_string),
         {:ok, result} <- insert_simulation_plan(repo_name(connection_string), simulation_plan) do
      {:ok, result}
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

  @doc false
  def prepare_post_rows(rows, base_time) when is_list(rows) and is_struct(base_time, DateTime) do
    {post_rows, record_rows, feed_item_rows} =
      Enum.reduce(rows, {[], [], []}, fn %{offset_ms: offset_ms, user_id: user_id},
                                         {post_acc, record_acc, feed_item_acc} ->
        did = Data.did_for_user_id(user_id)
        created_at = shifted_timestamp(base_time, offset_ms)
        indexed_at = indexed_timestamp(base_time, offset_ms)
        text = "Simulated post from user #{user_id}"
        record = Data.create_record(Data.post_type(), text: text, created_at: created_at)
        uri = at_uri(did, Data.post_type())
        cid = Data.cid_for_record(record)

        post_row = %{
          uri: uri,
          cid: cid,
          creator: did,
          text: text,
          createdAt: created_at,
          indexedAt: indexed_at,
          sortAt: created_at
        }

        record_row = %{
          uri: uri,
          cid: cid,
          did: did,
          json: Jason.encode!(record),
          indexedAt: indexed_at,
          rev: TID.new()
        }

        feed_item_row = %{
          uri: uri,
          cid: cid,
          type: "post",
          postUri: uri,
          originatorDid: did,
          sortAt: created_at
        }

        {[post_row | post_acc], [record_row | record_acc], [feed_item_row | feed_item_acc]}
      end)

    %{
      post_rows: post_rows,
      record_rows: record_rows,
      feed_item_rows: feed_item_rows
    }
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

  defp insert_simulation_plan(repo_name, %SimulationPlan{} = simulation_plan) do
    with_dynamic_repo(repo_name, fn ->
      posts = events_from_plan(simulation_plan.posts)
      follows = events_from_plan(simulation_plan.follows)
      sessions = events_from_plan(simulation_plan.sessions)

      actor_ids =
        actor_ids_from_posts(posts) ++
          actor_ids_from_follows(follows) ++
          actor_ids_from_sessions(sessions)

      actor_ids = Enum.uniq(actor_ids)

      insert_actor_rows(actor_ids)

      %{
        inserted_post_count: inserted_post_count,
        inserted_record_count: inserted_record_count,
        inserted_feed_item_count: inserted_feed_item_count
      } = insert_post_rows(posts)

      insert_follow_rows(follows)

      {:ok,
       %{
         inserted_actor_count: length(actor_ids),
         inserted_post_count: inserted_post_count,
         inserted_record_count: inserted_record_count,
         inserted_feed_item_count: inserted_feed_item_count,
         inserted_follow_count: length(follows),
         included_session_count: length(sessions)
       }}
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
        actor_row(user_id, indexed_at)
      end)

    insert_all_in_batches(Actor, actor_rows, on_conflict: :nothing, conflict_target: [:did])
  end

  defp insert_follow_rows(rows) do
    base_time = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    follow_rows =
      Enum.map(rows, fn %{offset_ms: offset_ms, actor_id: actor_id, subject_id: subject_id} ->
        follow_row(actor_id, subject_id, base_time, offset_ms)
      end)

    insert_all_in_batches(Follow, follow_rows, on_conflict: :nothing, conflict_target: [:uri])
  end

  defp insert_post_rows(rows) do
    base_time = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    %{post_rows: post_rows, record_rows: record_rows, feed_item_rows: feed_item_rows} =
      prepare_post_rows(rows, base_time)

    insert_all_in_batches(Post, post_rows, on_conflict: :nothing, conflict_target: [:uri])
    insert_all_in_batches(Record, record_rows, on_conflict: :nothing, conflict_target: [:uri])

    insert_all_in_batches(FeedItem, feed_item_rows,
      on_conflict: :nothing,
      conflict_target: [:uri]
    )

    %{
      inserted_post_count: length(post_rows),
      inserted_record_count: length(record_rows),
      inserted_feed_item_count: length(feed_item_rows)
    }
  end

  defp events_from_plan(nil), do: []
  defp events_from_plan(events) when is_list(events), do: events

  defp actor_ids_from_posts(posts) do
    Enum.map(posts, fn %{user_id: user_id} -> user_id end)
  end

  defp actor_ids_from_follows(follows) do
    Enum.flat_map(follows, fn %{actor_id: actor_id, subject_id: subject_id} ->
      [actor_id, subject_id]
    end)
  end

  defp actor_ids_from_sessions(sessions) do
    Enum.map(sessions, fn %{user_id: user_id} -> user_id end)
  end

  defp validate_connection_string("postgres://" <> _), do: :ok
  defp validate_connection_string("postgresql://" <> _), do: :ok
  defp validate_connection_string(_), do: {:error, "Connection string must be a postgres URL"}

  @doc false
  def actor_row(user_id, indexed_at) when is_integer(user_id) and is_binary(indexed_at) do
    %{
      did: Data.did_for_user_id(user_id),
      indexedAt: indexed_at,
      trustedVerifier: false
    }
  end

  @doc false
  def follow_row(actor_id, subject_id, base_time, offset_ms)
      when is_integer(actor_id) and is_integer(subject_id) and is_struct(base_time, DateTime) and
             is_integer(offset_ms) do
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
  end

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
