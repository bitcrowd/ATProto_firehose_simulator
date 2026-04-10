defmodule FirehoseSimulator.UserbaseImport do
  alias FirehoseSimulator.BulkCreation
  alias FirehoseSimulator.BulkCreation.DynamicRepo
  alias FirehoseSimulator.DatabaseConnection
  alias FirehoseSimulator.UserbaseMeta

  @spec import(String.t(), DatabaseConnection.t(), module(), module()) ::
          {:ok, map()} | {:error, String.t()}
  def import(
        meta_path,
        %DatabaseConnection{} = connection,
        repo \\ DynamicRepo,
        connector \\ BulkCreation
      )
      when is_binary(meta_path) and is_atom(repo) and is_atom(connector) do
    with {:ok, meta} <- UserbaseMeta.load_file(meta_path),
         :ok <- connector.connect(connection.connection_string),
         {:ok, :copied} <-
           with_dynamic_repo(connector.repo_name(connection.connection_string), fn ->
             with {:ok, _actor_result} <-
                    copy_csv(repo, copy_actor_sql(meta.files.actor.path), timeout: :infinity),
                  {:ok, _follow_result} <-
                    copy_csv(repo, copy_follow_sql(meta.files.follow.path), timeout: :infinity) do
               {:ok, :copied}
             end
           end) do
      {:ok,
       %{
         meta_path: meta_path,
         actor_csv_path: meta.files.actor.path,
         follow_csv_path: meta.files.follow.path,
         inserted_actor_count: meta.files.actor.row_count,
         inserted_follow_count: meta.files.follow.row_count
       }}
    end
  end

  @spec copy_actor_sql(String.t()) :: String.t()
  def copy_actor_sql(path) when is_binary(path) do
    "COPY bsky.actor (did, \"indexedAt\", \"trustedVerifier\") FROM " <>
      quoted_path(path) <> " WITH (FORMAT csv)"
  end

  @spec copy_follow_sql(String.t()) :: String.t()
  def copy_follow_sql(path) when is_binary(path) do
    "COPY bsky.follow (uri, cid, creator, \"subjectDid\", \"createdAt\", \"indexedAt\") FROM " <>
      quoted_path(path) <> " WITH (FORMAT csv)"
  end

  defp copy_csv(repo, sql, opts) do
    case repo.query(sql, [], opts) do
      {:ok, result} -> {:ok, result}
      {:error, %DBConnection.ConnectionError{} = error} -> {:error, Exception.message(error)}
      {:error, %Postgrex.Error{} = error} -> {:error, Exception.message(error)}
      {:error, reason} when is_binary(reason) -> {:error, reason}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  defp with_dynamic_repo(repo_name, fun) do
    previous_repo = DynamicRepo.get_dynamic_repo()
    DynamicRepo.put_dynamic_repo(repo_name)

    try do
      fun.()
    after
      DynamicRepo.put_dynamic_repo(previous_repo)
    end
  end

  defp quoted_path(path) do
    "'" <> String.replace(path, "'", "''") <> "'"
  end
end
