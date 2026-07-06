defmodule Mix.Tasks.Dataplane.Migrate do
  @moduledoc "Run bluesky database migrations via the upstream @atproto/bsky dataplane"

  use Mix.Task

  @shortdoc @moduledoc

  def run(_args) do
    db_url =
      Application.get_env(:firehose_simulator, FirehoseSimulator.Repo)[:url] ||
        Mix.raise("No database URL configured. Configure FirehoseSimulator.Repo")

    migrate_js = Path.join(File.cwd!(), "dataplane/migrate.js")

    case System.cmd("node", [migrate_js],
           env: [{"BSKY_DB_POSTGRES_URL", db_url}],
           into: IO.stream(:stdio, :line),
           stderr_to_stdout: true
         ) do
      {_, 0} ->
        :ok

      {_, status} ->
        Mix.raise("dataplane.migrate failed with exit code #{status}")
    end
  end
end
