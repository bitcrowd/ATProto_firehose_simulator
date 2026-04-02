defmodule FirehoseSimulator.BulkCreation.DynamicRepo do
  use Ecto.Repo,
    otp_app: :firehose_simulator,
    adapter: Ecto.Adapters.Postgres

  @spec connect(atom(), String.t()) :: {:ok, pid()} | {:error, String.t()}
  def connect(repo_name, connection_string)
      when is_atom(repo_name) and is_binary(connection_string) do
    case start_link(name: repo_name, url: connection_string, pool_size: 10) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, reason} -> {:error, format_start_error(reason)}
    end
  end

  defp format_start_error(%DBConnection.ConnectionError{} = error), do: Exception.message(error)
  defp format_start_error(%Postgrex.Error{} = error), do: Exception.message(error)

  defp format_start_error({%DBConnection.ConnectionError{} = error, _stacktrace}),
    do: Exception.message(error)

  defp format_start_error({%Postgrex.Error{} = error, _stacktrace}), do: Exception.message(error)

  defp format_start_error(error) do
    if is_exception(error), do: Exception.message(error), else: inspect(error)
  end
end
