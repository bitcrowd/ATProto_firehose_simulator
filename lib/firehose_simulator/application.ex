defmodule FirehoseSimulator.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    children =
      [
        FirehoseSimulatorWeb.Telemetry,
        {DNSCluster,
         query: Application.get_env(:firehose_simulator, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: FirehoseSimulator.PubSub},
        FirehoseSimulator.BulkCreation.RepoSupervisor,
        FirehoseSimulator.BulkCreation.State,
        FirehoseSimulator.Firehose.EventSupervisor,
        FirehoseSimulator.Firehose,
        # Start a worker by calling: FirehoseSimulator.Worker.start_link(arg)
        # {FirehoseSimulator.Worker, arg},
        # Start to serve requests, typically the last entry
        {PLC.OpLog, %{}},
        PLCWeb.Endpoint,
        PDSWeb.Endpoint,
        FirehoseSimulatorWeb.Endpoint
      ]
      |> maybe_add_startup_userbase_task()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: FirehoseSimulator.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    PLCWeb.Endpoint.config_change(changed, removed)
    PDSWeb.Endpoint.config_change(changed, removed)
    FirehoseSimulatorWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp create_startup_userbase do
    case FirehoseSimulator.create_userbase() do
      {:ok, result} ->
        Logger.info("startup userbase created: #{inspect(result)}")

      {:error, reason} ->
        Logger.error("startup userbase creation failed: #{reason}")
    end
  end

  defp maybe_add_startup_userbase_task(children) do
    if Application.get_env(:firehose_simulator, :create_startup_userbase?, true) do
      children ++ [{Task, &create_startup_userbase/0}]
    else
      children
    end
  end
end
