defmodule FirehoseSimulator.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  require Logger

  @file_log_handler :firehose_simulator_file_log
  @default_log_file "log/firehose_simulator.log"

  @impl true
  def start(_type, _args) do
    configure_file_logging()

    prometheus_port = Application.fetch_env!(:firehose_simulator, :prometheus_exporter_port)
    finch_pool_size = Application.fetch_env!(:firehose_simulator, :finch_pool_size)

    children =
      [
        FirehoseSimulator.Repo,
        {Finch,
         name: Dataplane.Finch,
         pools: %{
           default: [size: finch_pool_size]
         }},
        FirehoseSimulatorWeb.Telemetry,
        {DNSCluster,
         query: Application.get_env(:firehose_simulator, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: FirehoseSimulator.PubSub},
        {Registry, keys: :unique, name: FirehoseSimulator.Player.Registry},
        {DynamicSupervisor, name: FirehoseSimulator.PlayerSupervisor, strategy: :one_for_one},
        {Task.Supervisor, name: FirehoseSimulator.Player.TaskSupervisor},
        FirehoseSimulator.State,
        FirehoseSimulator.Metrics,
        {Bandit,
         plug: FirehoseSimulator.Metrics.PrometheusExporter,
         ip: {0, 0, 0, 0},
         port: prometheus_port},
        {PLC.OpLog, %{}},
        PLCWeb.Endpoint,
        PDSWeb.Endpoint,
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
    PLCWeb.Endpoint.config_change(changed, removed)
    PDSWeb.Endpoint.config_change(changed, removed)
    FirehoseSimulatorWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp configure_file_logging do
    log_file_path =
      Application.get_env(:firehose_simulator, :log_file_path, @default_log_file)
      |> timestamped_log_file_path()

    with :ok <- File.mkdir_p(Path.dirname(log_file_path)),
         :ok <- ensure_file_handler(log_file_path) do
      :ok
    else
      {:error, reason} ->
        Logger.warning("failed to enable file logging at #{log_file_path}: #{inspect(reason)}")
        :ok
    end
  end

  defp ensure_file_handler(log_file_path) do
    handler_config = %{
      config: %{type: {:file, String.to_charlist(log_file_path)}}
    }

    case :logger.add_handler(@file_log_handler, :logger_std_h, handler_config) do
      :ok ->
        :ok

      {:error, {:already_exist, @file_log_handler}} ->
        :ok = :logger.remove_handler(@file_log_handler)
        :logger.add_handler(@file_log_handler, :logger_std_h, handler_config)

      {:error, _reason} = error ->
        error
    end
  end

  defp timestamped_log_file_path(log_file_path) do
    timestamp = DateTime.utc_now() |> Calendar.strftime("%Y%m%dT%H%M%SZ")
    directory = Path.dirname(log_file_path)
    basename = Path.basename(log_file_path)

    Path.join(directory, "#{timestamp}_#{basename}")
  end
end
