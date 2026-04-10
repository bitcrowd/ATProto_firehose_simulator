defmodule FirehoseSimulator.BulkCreation.Vacuum do
  alias FirehoseSimulator.BulkCreation
  alias FirehoseSimulator.BulkCreation.DynamicRepo

  @spec run(String.t(), keyword()) :: {:ok, map()} | {:error, String.t()}
  def run(connection_string, opts) when is_binary(connection_string) and is_list(opts) do
    delete_userbase? = Keyword.get(opts, :delete_userbase?, false)
    vacuum_posts? = Keyword.get(opts, :vacuum_posts?, false)

    with :ok <- validate_requested_actions(delete_userbase?, vacuum_posts?),
         :ok <- BulkCreation.connect(connection_string) do
      repo_name = BulkCreation.repo_name(connection_string)

      with_dynamic_repo(repo_name, fn ->
        with {:ok, deleted} <- maybe_delete_userbase(delete_userbase?),
             {:ok, vacuum} <- maybe_vacuum_posts(vacuum_posts?) do
          {:ok,
           %{
             delete_userbase?: delete_userbase?,
             vacuum_posts?: vacuum_posts?,
             deleted: deleted,
             vacuum: vacuum
           }}
        end
      end)
    end
  end

  defp validate_requested_actions(false, false),
    do: {:error, "Select at least one vacuum action"}

  defp validate_requested_actions(_delete_userbase?, _vacuum_posts?), do: :ok

  defp maybe_delete_userbase(false), do: {:ok, nil}

  defp maybe_delete_userbase(true) do
    with {:ok, follows_deleted} <- delete_table("bsky.follow"),
         {:ok, posts_deleted} <- delete_table("bsky.post"),
         {:ok, actors_deleted} <- delete_table("bsky.actor") do
      {:ok, %{actors: actors_deleted, posts: posts_deleted, follows: follows_deleted}}
    end
  end

  defp maybe_vacuum_posts(false), do: {:ok, nil}

  defp maybe_vacuum_posts(true) do
    tables = ["bsky.post", "bsky.record", "bsky.feed_item"]

    Enum.reduce_while(tables, {:ok, []}, fn table, {:ok, vacuumed_tables} ->
      case DynamicRepo.query("VACUUM FULL #{table}", [], timeout: :infinity) do
        {:ok, _result} -> {:cont, {:ok, [table | vacuumed_tables]}}
        {:error, reason} -> {:halt, {:error, format_db_error(reason)}}
      end
    end)
    |> case do
      {:ok, vacuumed_tables} ->
        {:ok, %{tables: Enum.reverse(vacuumed_tables), mode: "full"}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp delete_table(table_name) do
    case DynamicRepo.query("DELETE FROM #{table_name}") do
      {:ok, %{num_rows: num_rows}} -> {:ok, num_rows}
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
