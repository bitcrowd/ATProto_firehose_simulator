defmodule FirehoseSimulator.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      FirehoseSimulatorWeb.Telemetry,
      {DNSCluster,
       query: Application.get_env(:firehose_simulator, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: FirehoseSimulator.PubSub},
      FirehoseSimulator.Firehose.EventSupervisor,
      FirehoseSimulator.Firehose,
      # Start a worker by calling: FirehoseSimulator.Worker.start_link(arg)
      # {FirehoseSimulator.Worker, arg},
      # Start to serve requests, typically the last entry
      {PLC.OpLog, %{}},
      PLCWeb.Endpoint,
      FirehoseSimulatorWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: FirehoseSimulator.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    FirehoseSimulatorWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
