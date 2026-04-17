defmodule FirehoseSimulator.BaseData.UserbaseImport do
  alias FirehoseSimulator.BaseData.UserbaseMeta
  alias FirehoseSimulator.Repo

  @spec import(String.t(), module()) ::
          {:ok, map()} | {:error, String.t()}
  def import(meta_path, repo \\ Repo) when is_binary(meta_path) and is_atom(repo) do
    with {:ok, meta} <- UserbaseMeta.load_file(meta_path),
         {:ok, :copied} <- copy_userbase_files(repo, meta) do
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

  @spec import_from_meta_json(String.t(), module(), keyword()) ::
          {:ok, map()} | {:error, String.t()}
  def import_from_meta_json(meta_json, repo \\ Repo, opts \\ [])
      when is_binary(meta_json) and is_atom(repo) and is_list(opts) do
    copy_fun = Keyword.get(opts, :copy_fun, &copy_userbase_files/2)

    with {:ok, meta} <-
           UserbaseMeta.load(meta_json, validate_files: Keyword.get(opts, :validate_files, true)),
         {:ok, :copied} <- copy_fun.(repo, meta) do
      {:ok,
       %{
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

  defp copy_userbase_files(repo, meta) do
    with {:ok, _actor_result} <-
           copy_csv(repo, copy_actor_sql(meta.files.actor.path), timeout: :infinity),
         {:ok, _follow_result} <-
           copy_csv(repo, copy_follow_sql(meta.files.follow.path), timeout: :infinity) do
      {:ok, :copied}
    end
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

  defp quoted_path(path) do
    "'" <> String.replace(path, "'", "''") <> "'"
  end
end
