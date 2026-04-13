defmodule FirehoseSimulator.BulkCreation.Vacuum do
  alias FirehoseSimulator.BulkCreation
  alias FirehoseSimulator.BulkCreation.DynamicRepo

  @spec run(String.t(), keyword()) :: {:ok, map()} | {:error, String.t()}
  def run(connection_string, opts) when is_binary(connection_string) and is_list(opts) do
    delete_userbase? = Keyword.get(opts, :delete_userbase?, false)
    delete_posts? = Keyword.get(opts, :delete_posts?, false)

    with :ok <- validate_requested_actions(delete_userbase?, delete_posts?),
         :ok <- BulkCreation.connect(connection_string) do
      repo_name = BulkCreation.repo_name(connection_string)

      with_dynamic_repo(repo_name, fn ->
        with {:ok, deleted_userbase} <- maybe_delete_userbase(delete_userbase?),
             {:ok, deleted_posts} <- maybe_delete_posts(delete_posts?) do
          {:ok,
           %{
             delete_userbase?: delete_userbase?,
             delete_posts?: delete_posts?,
             deleted_userbase: deleted_userbase,
             deleted_posts: deleted_posts
           }}
        end
      end)
    end
  end

  defp validate_requested_actions(false, false),
    do: {:error, "Select at least one vacuum action"}

  defp validate_requested_actions(_delete_userbase?, _delete_posts?), do: :ok

  defp maybe_delete_userbase(false), do: {:ok, nil}

  defp maybe_delete_userbase(true) do
    truncate_tables(["bsky.follow", "bsky.actor"])
  end

  defp maybe_delete_posts(false), do: {:ok, nil}

  defp maybe_delete_posts(true) do
    truncate_tables(["bsky.feed_item", "bsky.record", "bsky.post"])
  end

  defp truncate_tables(tables) when is_list(tables) do
    Enum.reduce_while(tables, {:ok, []}, fn table, {:ok, truncated_tables} ->
      case truncate_table(table) do
        {:ok, _result} -> {:cont, {:ok, [table | truncated_tables]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, truncated_tables} ->
        {:ok, %{tables: Enum.reverse(truncated_tables)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp truncate_table(table_name) do
    case DynamicRepo.query("TRUNCATE TABLE #{table_name}", [], timeout: :infinity) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, format_db_error(reason)}
    end
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

  defp format_db_error(%Postgrex.Error{} = error), do: Exception.message(error)
  defp format_db_error(%DBConnection.ConnectionError{} = error), do: Exception.message(error)
  defp format_db_error(error) when is_exception(error), do: Exception.message(error)
  defp format_db_error(error), do: inspect(error)
end
