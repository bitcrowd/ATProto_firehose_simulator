defmodule FirehoseSimulator.BulkCreation.DynamicRepo do
  use Ecto.Repo,
    otp_app: :firehose_simulator,
    adapter: Ecto.Adapters.Postgres
end
