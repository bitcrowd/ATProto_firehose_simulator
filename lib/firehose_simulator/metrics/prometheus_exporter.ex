defmodule FirehoseSimulator.Metrics.PrometheusExporter do
  @moduledoc false

  import Plug.Conn

  alias FirehoseSimulator.Metrics

  def init(opts), do: opts

  def call(%Plug.Conn{method: "GET", request_path: "/metrics"} = conn, _opts) do
    snapshot = Metrics.snapshot()

    body =
      [
        "# TYPE firehose_simulator_json_files_loaded_total counter\n",
        metric("firehose_simulator_json_files_loaded_total", snapshot.json_files_loaded),
        "# TYPE firehose_simulator_player_load_total counter\n",
        metric("firehose_simulator_player_load_total", snapshot.player_load),
        "# TYPE firehose_simulator_player_start_total counter\n",
        metric("firehose_simulator_player_start_total", snapshot.player_start),
        "# TYPE firehose_simulator_player_pause_total counter\n",
        metric("firehose_simulator_player_pause_total", snapshot.player_pause),
        "# TYPE firehose_simulator_player_stop_total counter\n",
        metric("firehose_simulator_player_stop_total", snapshot.player_stop),
        "# TYPE firehose_simulator_event_feeder_inject_total counter\n",
        metric(
          "firehose_simulator_event_feeder_inject_total",
          snapshot.event_feeder_inject_count
        ),
        "# TYPE firehose_simulator_event_feeder_sessions_started_total counter\n",
        metric(
          "firehose_simulator_event_feeder_sessions_started_total",
          snapshot.event_feeder_sessions_started
        ),
        "# TYPE firehose_simulator_event_feeder_posts_dispatch_total counter\n",
        metric(
          "firehose_simulator_event_feeder_posts_dispatch_total",
          snapshot.event_feeder_posts_dispatch_count
        ),
        "# TYPE firehose_simulator_event_feeder_posts_dispatched_total counter\n",
        metric(
          "firehose_simulator_event_feeder_posts_dispatched_total",
          snapshot.event_feeder_posts_dispatched
        ),
        "# TYPE firehose_simulator_event_feeder_posts_complete_total counter\n",
        metric(
          "firehose_simulator_event_feeder_posts_complete_total",
          snapshot.event_feeder_posts_complete_count
        ),
        "# TYPE firehose_simulator_event_feeder_posts_ok_total counter\n",
        metric("firehose_simulator_event_feeder_posts_ok_total", snapshot.event_feeder_posts_ok),
        "# TYPE firehose_simulator_event_feeder_posts_error_total counter\n",
        metric(
          "firehose_simulator_event_feeder_posts_error_total",
          snapshot.event_feeder_posts_error
        ),
        "# TYPE firehose_simulator_event_feeder_follows_dispatch_total counter\n",
        metric(
          "firehose_simulator_event_feeder_follows_dispatch_total",
          snapshot.event_feeder_follows_dispatch_count
        ),
        "# TYPE firehose_simulator_event_feeder_follows_dispatched_total counter\n",
        metric(
          "firehose_simulator_event_feeder_follows_dispatched_total",
          snapshot.event_feeder_follows_dispatched
        ),
        "# TYPE firehose_simulator_event_feeder_follows_complete_total counter\n",
        metric(
          "firehose_simulator_event_feeder_follows_complete_total",
          snapshot.event_feeder_follows_complete_count
        ),
        "# TYPE firehose_simulator_event_feeder_follows_ok_total counter\n",
        metric(
          "firehose_simulator_event_feeder_follows_ok_total",
          snapshot.event_feeder_follows_ok
        ),
        "# TYPE firehose_simulator_event_feeder_follows_error_total counter\n",
        metric(
          "firehose_simulator_event_feeder_follows_error_total",
          snapshot.event_feeder_follows_error
        ),
        "# TYPE firehose_simulator_worker_query_total counter\n",
        metric("firehose_simulator_worker_query_total", snapshot.worker_query_total_count),
        "# TYPE firehose_simulator_worker_query_rows_total counter\n",
        metric("firehose_simulator_worker_query_rows_total", snapshot.worker_query_rows),
        "# TYPE firehose_simulator_worker_query_latency_ms_total counter\n",
        metric(
          "firehose_simulator_worker_query_latency_ms_total",
          snapshot.worker_query_total_latency_ms
        ),
        "# TYPE firehose_simulator_worker_query_lag_ms histogram\n",
        histogram_metrics(
          "firehose_simulator_worker_query_lag_ms",
          "kind",
          "session_request",
          snapshot.worker_query_lag_bucket_counts,
          snapshot.worker_query_total_count,
          snapshot.worker_query_lag_total_ms
        ),
        "# TYPE firehose_simulator_worker_cycle_total counter\n",
        metric("firehose_simulator_worker_cycle_total", snapshot.worker_cycle_count),
        "# TYPE firehose_simulator_worker_cycle_session_count_total counter\n",
        metric(
          "firehose_simulator_worker_cycle_session_count_total",
          snapshot.worker_cycle_session_count
        ),
        "# TYPE firehose_simulator_worker_cycle_ok_total counter\n",
        metric("firehose_simulator_worker_cycle_ok_total", snapshot.worker_cycle_ok),
        "# TYPE firehose_simulator_worker_cycle_errors_total counter\n",
        metric("firehose_simulator_worker_cycle_errors_total", snapshot.worker_cycle_errors),
        "# TYPE firehose_simulator_worker_cycle_completed_total counter\n",
        metric(
          "firehose_simulator_worker_cycle_completed_total",
          snapshot.worker_cycle_completed
        ),
        "# TYPE firehose_simulator_worker_cycle_timeouts_total counter\n",
        metric("firehose_simulator_worker_cycle_timeouts_total", snapshot.worker_cycle_timeouts),
        "# TYPE firehose_simulator_worker_cycle_duration_ms_total counter\n",
        metric(
          "firehose_simulator_worker_cycle_duration_ms_total",
          snapshot.worker_cycle_duration_ms
        ),
        "# TYPE firehose_simulator_worker_query_by_status gauge\n",
        labelled_metrics(
          "firehose_simulator_worker_query_by_status",
          "status",
          snapshot.worker_query_by_status
        ),
        "# TYPE firehose_simulator_worker_cycle_by_partition gauge\n",
        labelled_metrics(
          "firehose_simulator_worker_cycle_by_partition",
          "partition",
          snapshot.worker_cycle_by_partition
        ),
        "# TYPE firehose_simulator_worker_query_window_query_count gauge\n",
        metric(
          "firehose_simulator_worker_query_window_query_count",
          snapshot.worker_query_window_stats.query_count
        ),
        "# TYPE firehose_simulator_worker_query_window_avg_latency_ms gauge\n",
        metric(
          "firehose_simulator_worker_query_window_avg_latency_ms",
          snapshot.worker_query_window_stats.avg_latency_ms
        ),
        "# TYPE firehose_simulator_worker_query_window_p95_latency_ms gauge\n",
        metric(
          "firehose_simulator_worker_query_window_p95_latency_ms",
          snapshot.worker_query_window_stats.p95_latency_ms
        ),
        "# TYPE firehose_simulator_worker_query_window_p99_latency_ms gauge\n",
        metric(
          "firehose_simulator_worker_query_window_p99_latency_ms",
          snapshot.worker_query_window_stats.p99_latency_ms
        ),
        "# TYPE firehose_simulator_worker_query_window_avg_lag_ms gauge\n",
        metric(
          "firehose_simulator_worker_query_window_avg_lag_ms",
          snapshot.worker_query_window_stats.avg_lag_ms
        ),
        "# TYPE firehose_simulator_worker_query_window_p95_lag_ms gauge\n",
        metric(
          "firehose_simulator_worker_query_window_p95_lag_ms",
          snapshot.worker_query_window_stats.p95_lag_ms
        ),
        "# TYPE firehose_simulator_worker_query_window_max_lag_ms gauge\n",
        metric(
          "firehose_simulator_worker_query_window_max_lag_ms",
          snapshot.worker_query_window_stats.max_lag_ms
        ),
        "# TYPE firehose_simulator_worker_query_window_error_rate_pct gauge\n",
        metric(
          "firehose_simulator_worker_query_window_error_rate_pct",
          snapshot.worker_query_window_stats.error_rate_pct
        ),
        "# TYPE firehose_simulator_worker_query_window_timeout_rate_pct gauge\n",
        metric(
          "firehose_simulator_worker_query_window_timeout_rate_pct",
          snapshot.worker_query_window_stats.timeout_rate_pct
        ),
        "# TYPE firehose_simulator_worker_query_window_ok_count gauge\n",
        metric(
          "firehose_simulator_worker_query_window_ok_count",
          snapshot.worker_query_window_stats.ok_count
        ),
        "# TYPE firehose_simulator_worker_query_window_error_count gauge\n",
        metric(
          "firehose_simulator_worker_query_window_error_count",
          snapshot.worker_query_window_stats.error_count
        ),
        "# TYPE firehose_simulator_worker_query_window_timeout_count gauge\n",
        metric(
          "firehose_simulator_worker_query_window_timeout_count",
          snapshot.worker_query_window_stats.timeout_count
        ),
        "# TYPE firehose_simulator_worker_query_window_exit_count gauge\n",
        metric(
          "firehose_simulator_worker_query_window_exit_count",
          snapshot.worker_query_window_stats.exit_count
        ),
        "# TYPE firehose_simulator_active_sessions gauge\n",
        metric("firehose_simulator_active_sessions", snapshot.active_sessions_total),
        "# TYPE firehose_simulator_player_active_sessions gauge\n",
        labelled_metrics(
          "firehose_simulator_player_active_sessions",
          "player_id",
          snapshot.active_sessions_by_player
        )
      ]
      |> IO.iodata_to_binary()

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, body)
  end

  def call(conn, _opts), do: send_resp(conn, 404, "not found")

  defp metric(name, value) do
    [name, " ", to_value(value), "\n"]
  end

  defp labelled_metrics(name, label, values) when map_size(values) == 0 do
    [name, "{", label, "=\"none\"} 0\n"]
  end

  defp labelled_metrics(name, label, values) do
    Enum.map(values, fn {key, value} ->
      [name, "{", label, "=\"", to_string(key), "\"} ", to_value(value), "\n"]
    end)
  end

  defp histogram_metrics(name, label, label_value, bucket_counts, count, sum) do
    [
      histogram_bucket_metrics(name, label, label_value, bucket_counts),
      [name, "_count{", label, "=\"", label_value, "\"} ", to_value(count), "\n"],
      [name, "_sum{", label, "=\"", label_value, "\"} ", to_value(sum), "\n"]
    ]
  end

  defp histogram_bucket_metrics(name, label, label_value, bucket_counts) do
    bucket_counts
    |> Enum.sort_by(fn {bucket, _count} -> histogram_bucket_sort_key(bucket) end)
    |> Enum.map(fn {bucket, count} ->
      [
        name,
        "_bucket{",
        label,
        "=\"",
        label_value,
        "\",le=\"",
        bucket,
        "\"} ",
        to_value(count),
        "\n"
      ]
    end)
  end

  defp histogram_bucket_sort_key("+Inf"), do: {1, 0}
  defp histogram_bucket_sort_key(bucket), do: {0, String.to_integer(bucket)}

  defp to_value(value) when is_integer(value), do: Integer.to_string(value)
  defp to_value(value) when is_float(value), do: :erlang.float_to_binary(value, [:compact])
  defp to_value(value), do: to_string(value)
end
