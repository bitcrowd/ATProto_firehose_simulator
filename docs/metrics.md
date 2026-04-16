# Metrics

The simulator provides metrics for plan loading, player lifecycle, event feeding, worker throughput, and worker lag.
A Prometheus and Grafana setup with Docker compose and a Grafana dashboard are available under `infra/`.

## Prometheus Metrics

### Lifecycle And Player State

| Metric                                                       | Type    | Meaning                                                                                              |
| ---                                                          | ---     | ---                                                                                                  |
| `firehose_simulator_json_files_loaded_total`                 | counter | Number of JSON plan files loaded into the app.                                                       |
| `firehose_simulator_player_load_total`                       | counter | Number of player load actions processed.                                                             |
| `firehose_simulator_player_start_total`                      | counter | Number of player start actions processed.                                                            |
| `firehose_simulator_player_pause_total`                      | counter | Number of player pause actions processed.                                                            |
| `firehose_simulator_player_stop_total`                       | counter | Number of player stop actions processed.                                                             |
| `firehose_simulator_active_sessions`                         | gauge   | Current total number of active sessions across all players derived from telemetry-fed metrics state. |
| `firehose_simulator_player_active_sessions{player_id="..."}` | gauge   | Current number of active sessions for one player derived from telemetry-fed metrics state.           |

### Event Feeder Metrics

| Metric                                                     | Type    | Meaning                                                            |
| ---                                                        | ---     | ---                                                                |
| `firehose_simulator_event_feeder_inject_total`             | counter | Number of event feeder inject cycles run.                          |
| `firehose_simulator_event_feeder_sessions_started_total`   | counter | Total sessions started by inject cycles.                           |
| `firehose_simulator_event_feeder_posts_dispatch_total`     | counter | Number of post dispatch batches attempted.                         |
| `firehose_simulator_event_feeder_posts_dispatched_total`   | counter | Total post events dispatched across all post dispatch batches.     |
| `firehose_simulator_event_feeder_posts_complete_total`     | counter | Number of post completion batches recorded.                        |
| `firehose_simulator_event_feeder_posts_ok_total`           | counter | Total post events completed successfully.                          |
| `firehose_simulator_event_feeder_posts_error_total`        | counter | Total post events completed with error.                            |
| `firehose_simulator_event_feeder_follows_dispatch_total`   | counter | Number of follow dispatch batches attempted.                       |
| `firehose_simulator_event_feeder_follows_dispatched_total` | counter | Total follow events dispatched across all follow dispatch batches. |
| `firehose_simulator_event_feeder_follows_complete_total`   | counter | Number of follow completion batches recorded.                      |
| `firehose_simulator_event_feeder_follows_ok_total`         | counter | Total follow events completed successfully.                        |
| `firehose_simulator_event_feeder_follows_error_total`      | counter | Total follow events completed with error.                          |

### Worker Query Totals

| Metric                                                                            | Type    | Meaning                                                      |
| ---                                                                               | ---     | ---                                                          |
| `firehose_simulator_worker_query_total`                                           | counter | Total worker query executions.                               |
| `firehose_simulator_worker_query_rows_total`                                      | counter | Total rows returned across worker queries.                   |
| `firehose_simulator_worker_query_latency_ms_total`                                | counter | Sum of worker query latency in milliseconds.                 |
| `firehose_simulator_worker_query_by_status{status="ok\\|timeout\\|exit\\|error"}` | gauge   | Current cumulative query count grouped by normalized status. |

### Worker Query Lag Histogram

| Metric                                                                           | Type             | Meaning                                                                        |
| ---                                                                              | ---              | ---                                                                            |
| `firehose_simulator_worker_query_lag_ms_bucket{kind="session_request",le="..."}` | histogram bucket | Cumulative count of worker query lag samples at or below each bucket boundary. |
| `firehose_simulator_worker_query_lag_ms_count{kind="session_request"}`           | histogram count  | Total number of worker query lag samples.                                      |
| `firehose_simulator_worker_query_lag_ms_sum{kind="session_request"}`             | histogram sum    | Sum of all worker query lag values in milliseconds.                            |

Histogram bucket boundaries:

| `le` value |
| ---        |
| `0`        |
| `10`       |
| `50`       |
| `100`      |
| `500`      |
| `1000`     |
| `5000`     |
| `10000`    |
| `+Inf`     |

Lag here means how far behind schedule the worker was when handling a due session request.

### Worker Cycle Totals

| Metric                                                          | Type    | Meaning                                                            |
| ---                                                             | ---     | ---                                                                |
| `firehose_simulator_worker_cycle_total`                         | counter | Total worker cycles run.                                           |
| `firehose_simulator_worker_cycle_session_count_total`           | counter | Total due sessions processed across worker cycles.                 |
| `firehose_simulator_worker_cycle_ok_total`                      | counter | Total successful session operations across worker cycles.          |
| `firehose_simulator_worker_cycle_errors_total`                  | counter | Total errored session operations across worker cycles.             |
| `firehose_simulator_worker_cycle_completed_total`               | counter | Total sessions marked completed across worker cycles.              |
| `firehose_simulator_worker_cycle_timeouts_total`                | counter | Total timed-out session operations across worker cycles.           |
| `firehose_simulator_worker_cycle_duration_ms_total`             | counter | Sum of worker cycle durations in milliseconds.                     |
| `firehose_simulator_worker_cycle_by_partition{partition="..."}` | gauge   | Current cumulative worker cycle count grouped by worker partition. |

### Rolling Worker Query Window

These gauges are computed from the last 60 seconds of worker query samples at scrape time.

| Metric                                                    | Type  | Meaning                                                                                        |
| ---                                                       | ---   | ---                                                                                            |
| `firehose_simulator_worker_query_window_query_count`      | gauge | Number of worker query samples currently in the 60-second window.                              |
| `firehose_simulator_worker_query_window_avg_latency_ms`   | gauge | Average worker query latency in the current window.                                            |
| `firehose_simulator_worker_query_window_p95_latency_ms`   | gauge | 95th percentile worker query latency in the current window.                                    |
| `firehose_simulator_worker_query_window_p99_latency_ms`   | gauge | 99th percentile worker query latency in the current window.                                    |
| `firehose_simulator_worker_query_window_avg_lag_ms`       | gauge | Average worker query lag in the current window.                                                |
| `firehose_simulator_worker_query_window_p95_lag_ms`       | gauge | 95th percentile worker query lag in the current window.                                        |
| `firehose_simulator_worker_query_window_max_lag_ms`       | gauge | Maximum worker query lag in the current window.                                                |
| `firehose_simulator_worker_query_window_error_rate_pct`   | gauge | Error rate for the current window, where `error`, `timeout`, and `exit` all count as failures. |
| `firehose_simulator_worker_query_window_timeout_rate_pct` | gauge | Timeout rate for the current window.                                                           |
| `firehose_simulator_worker_query_window_ok_count`         | gauge | Number of `ok` query samples in the current window.                                            |
| `firehose_simulator_worker_query_window_error_count`      | gauge | Number of `error` query samples in the current window.                                         |
| `firehose_simulator_worker_query_window_timeout_count`    | gauge | Number of `timeout` query samples in the current window.                                       |
| `firehose_simulator_worker_query_window_exit_count`       | gauge | Number of `exit` query samples in the current window.                                          |

