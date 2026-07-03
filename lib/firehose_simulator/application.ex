defmodule FirehoseSimulator.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  alias FirehoseSimulator.RunStorage
  require Logger

  @file_log_handler :firehose_simulator_file_log

  @impl true
  def start(_type, _args) do
    {run_storage_directory, active_log_file_path} = configure_run_storage()

    prometheus_port = Application.fetch_env!(:firehose_simulator, :prometheus_exporter_port)
    finch_pool_size = Application.fetch_env!(:firehose_simulator, :finch_pool_size)

    log_startup_configuration(run_storage_directory, active_log_file_path)

    children =
      player_infrastructure(run_storage_directory) ++
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

  def startup_configuration(run_storage_directory, active_log_file_path) do
    plc_config = Application.get_env(:firehose_simulator, :plc, [])
    repo_config = Application.fetch_env!(:firehose_simulator, FirehoseSimulator.Repo)
    dataplane_url = Application.fetch_env!(:firehose_simulator, :dataplane_url)

    %{
      runs_root: Application.get_env(:firehose_simulator, :runs_root, Path.expand("runs")),
      run_storage_directory: run_storage_directory,
      default_userbase_json_path:
        Application.fetch_env!(:firehose_simulator, :default_userbase_json_path),
      log_file_path: active_log_file_path,
      database_url: Keyword.get(repo_config, :url),
      database_pool_size: Keyword.get(repo_config, :pool_size),
      dataplane_url: dataplane_url,
      finch_pool_size: Application.fetch_env!(:firehose_simulator, :finch_pool_size),
      prometheus_exporter_port:
        Application.fetch_env!(:firehose_simulator, :prometheus_exporter_port),
      plc_multikey: Keyword.get(plc_config, :multikey),
      plc_private_hex: Keyword.get(plc_config, :private_hex)
    }
  end

  defp log_startup_configuration(run_storage_directory, active_log_file_path) do
    config =
      startup_configuration(run_storage_directory, active_log_file_path)
      |> inspect(pretty: true, limit: :infinity)

    Logger.info("startup configuration:\n#{config}")
  end

  defp configure_run_storage do
    if FirehoseSimulator.run_storage_enabled?() do
      configure_file_logging()
    else
      {nil, nil}
    end
  end

  defp configure_file_logging do
    run_storage_directory = RunStorage.timestamped_directory()
    configured_log_file_path = Application.fetch_env!(:firehose_simulator, :log_file_path)
    log_file_name = Path.basename(configured_log_file_path)

    with {:ok, _run_storage_directory} <- RunStorage.ensure_run_directory(run_storage_directory),
         {:ok, path} <- RunStorage.default_log_file_path(run_storage_directory, log_file_name),
         :ok <- ensure_file_handler(path) do
      {run_storage_directory, path}
    else
      {:error, reason} ->
        Logger.warning("failed to enable file logging: #{inspect(reason)}")
        {run_storage_directory, nil}
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

  defp player_infrastructure(run_storage_directory) do
    if Application.get_env(:firehose_simulator, :start_player_infrastructure, true) do
      [
        {Registry, keys: :unique, name: FirehoseSimulator.Player.Registry},
        {DynamicSupervisor, name: FirehoseSimulator.PlayerSupervisor, strategy: :one_for_one},
        {Task.Supervisor, name: FirehoseSimulator.Player.TaskSupervisor},
        {FirehoseSimulator.State, run_storage_directory: run_storage_directory}
      ]
    else
      []
    end
  end
end
