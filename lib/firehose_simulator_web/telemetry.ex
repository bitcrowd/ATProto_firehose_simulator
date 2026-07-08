defmodule FirehoseSimulatorWeb.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      # Telemetry poller will execute the given period measurements
      # every 10_000ms. Learn more here: https://hexdocs.pm/telemetry_metrics
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000},
      {TelemetryMetricsPrometheus.Core, metrics: prometheus_metrics()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # Phoenix Metrics
      summary("phoenix.endpoint.start.system_time",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.start.system_time",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.exception.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.socket_connected.duration",
        unit: {:native, :millisecond}
      ),
      sum("phoenix.socket_drain.count"),
      summary("phoenix.channel_joined.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.channel_handled_in.duration",
        tags: [:event],
        unit: {:native, :millisecond}
      ),

      # VM Metrics
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io")
    ]
  end

  def prometheus_metrics do
    [
      counter("firehose_simulator.json.file.loaded.count"),
      counter("firehose_simulator.player.load.count"),
      counter("firehose_simulator.player.start.count"),
      counter("firehose_simulator.player.pause.count"),
      counter("firehose_simulator.player.stop.count"),
      sum("firehose_simulator.player.stop.active_sessions_cleared"),
      counter("firehose_simulator.event_feeder.inject.count"),
      sum("firehose_simulator.event_feeder.inject.sessions_started"),
      counter("firehose_simulator.event_feeder.posts.dispatch.count"),
      sum("firehose_simulator.event_feeder.posts.dispatch.events_dispatched"),
      counter("firehose_simulator.event_feeder.posts.complete.count"),
      sum("firehose_simulator.event_feeder.posts.complete.ok"),
      sum("firehose_simulator.event_feeder.posts.complete.error"),
      counter("firehose_simulator.event_feeder.follows.dispatch.count"),
      sum("firehose_simulator.event_feeder.follows.dispatch.events_dispatched"),
      counter("firehose_simulator.event_feeder.follows.complete.count"),
      sum("firehose_simulator.event_feeder.follows.complete.ok"),
      sum("firehose_simulator.event_feeder.follows.complete.error"),
      counter("firehose_simulator.worker.query.count",
        tags: [:status],
        tag_values: &worker_query_tag_values/1
      ),
      distribution("firehose_simulator.worker.query.latency_ms",
        reporter_options: [buckets: [5, 10, 25, 50, 100, 250, 500, 1_000, 5_000, 10_000]],
        tags: [:status],
        tag_values: &worker_query_tag_values/1
      ),
      distribution("firehose_simulator.worker.query.rows",
        reporter_options: [buckets: [1, 10, 100, 1_000, 10_000]],
        tags: [:status],
        tag_values: &worker_query_tag_values/1
      ),
      distribution("firehose_simulator.worker.query.lag_ms",
        reporter_options: [buckets: [0, 10, 50, 100, 500, 1_000, 5_000, 10_000]],
        tags: [:kind],
        tag_values: &worker_query_lag_tag_values/1,
        description: "Worker query lag in ms (how far behind schedule)"
      ),
      counter("firehose_simulator.worker.cycle.count",
        tags: [:partition],
        tag_values: &worker_cycle_tag_values/1
      ),
      sum("firehose_simulator.worker.cycle.session_count"),
      sum("firehose_simulator.worker.cycle.ok"),
      sum("firehose_simulator.worker.cycle.errors"),
      sum("firehose_simulator.worker.cycle.completed"),
      sum("firehose_simulator.worker.cycle.timeouts"),
      distribution("firehose_simulator.worker.cycle.duration_ms",
        reporter_options: [buckets: [5, 10, 25, 50, 100, 250, 500, 1_000, 5_000]]
      ),
      last_value("firehose_simulator.active_sessions.count")
    ]
  end

  defp periodic_measurements do
    [{FirehoseSimulator.Metrics, :emit_active_sessions, []}]
  end

  defp worker_query_tag_values(metadata) do
    %{status: to_string(Map.get(metadata, :status, :unknown))}
  end

  defp worker_cycle_tag_values(metadata) do
    %{partition: to_string(Map.get(metadata, :partition, "unknown"))}
  end

  defp worker_query_lag_tag_values(_metadata) do
    %{kind: "session_request"}
  end
end
