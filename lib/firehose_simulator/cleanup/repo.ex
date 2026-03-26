defmodule FirehoseSimulator.Cleanup.Repo do
  use Ecto.Repo,
    otp_app: :firehose_simulator,
    adapter: Ecto.Adapters.Postgres

  @dynamic_repo_name :firehose_simulator_cleanup_dynamic_repo

  def with_dynamic_repo(opts, callback) when is_list(opts) and is_function(callback, 0) do
    default_dynamic_repo = get_dynamic_repo()
    start_opts = Keyword.merge([name: @dynamic_repo_name, pool_size: 1], opts)

    case start_link(start_opts) do
      {:ok, repo} ->
        try do
          put_dynamic_repo(@dynamic_repo_name)
          {:ok, callback.()}
        after
          put_dynamic_repo(default_dynamic_repo)
          Supervisor.stop(repo)
        end

      {:error, {:already_started, _pid}} ->
        {:error, "Cleanup is already running. Wait for the current cleanup request to finish."}

      {:error, error} ->
        {:error, Exception.message(error)}
    end
  end
end
