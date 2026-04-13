# Metrics

## Purpose

Metrics provide runtime observability for plan loading and live playback activity.

## Modules and Assets

- `FirehoseSimulator.Metrics`
- `FirehoseSimulator.PrometheusExporter`
- `FirehoseSimulatorWeb.MetricsLive`
- `infra/prometheus.yml`
- `infra/docker-compose.yml` (Prometheus/Grafana local stack)
- `infra/firesim-1775727593906.json` (portable Grafana dashboard import)

## Public Interfaces

- `FirehoseSimulator.Metrics.increment/2`
- `FirehoseSimulator.Metrics.snapshot/0`
- HTTP `GET /metrics` served by `FirehoseSimulator.PrometheusExporter`

## Telemetry and Metric Parameters

Detailed emitted telemetry event inventory and event-to-metric mapping:

- `docs/telemetry-events.md`

### Telemetry Events Consumed

- `[:firehose_simulator, :event_feeder, :inject]`
- `[:firehose_simulator, :event_feeder, :posts, :dispatch]`
- `[:firehose_simulator, :event_feeder, :posts, :complete]`
- `[:firehose_simulator, :event_feeder, :follows, :dispatch]`
- `[:firehose_simulator, :event_feeder, :follows, :complete]`
- `[:firehose_simulator, :worker, :query]`
- `[:firehose_simulator, :worker, :cycle]`

### Core Counters

- JSON load count
- Player start/stop/reset counts
- Event feeder session injection totals
- Event feeder post/follow dispatch and completion totals
- Worker query totals (count, rows, latency)
- Worker cycle totals (count, session_count, ok/errors/completed/timeouts, duration)

### Labelled and Windowed Metrics

- query totals by status (`ok`, `timeout`, `exit`, `error`)
- cycle totals by partition
- rolling worker query window stats over the configured window (`@worker_query_window_ms`, currently 60_000 ms)

## Runtime Behavior

1. `Metrics` starts as a GenServer and attaches telemetry handlers.
2. Application code and telemetry events update counters through async casts.
3. `snapshot/0` prunes stale query-window samples and returns a presentable state map.
4. `PrometheusExporter` converts snapshot values into Prometheus text format.
5. `/metrics` returns `text/plain` with counters and gauges; unknown routes return 404 in the plug.

## Failure and Edge Behavior

- Telemetry handler re-attachment handles `:already_exists` by detach/attach.
- Empty labelled maps are exported as a sentinel label/value pair (`...{label="none"} 0`).
- Non-integer measurement inputs are normalized to `0` in aggregation helpers.

## Grafana Dashboard Import

- Import `infra/firesim-1775727593906.json` through Grafana's dashboard import flow.
- The dashboard uses Grafana's `${DS_PROMETHEUS}` datasource input placeholder instead of a hardcoded datasource UID.
- On import, map `DS_PROMETHEUS` to the Prometheus datasource available in that Grafana instance.
- If you re-export the dashboard from Grafana, check the JSON before committing it:
  - there should be no concrete Prometheus datasource UIDs
  - the file should still contain `${DS_PROMETHEUS}`
  - panel targets should inherit the panel datasource instead of carrying their own datasource overrides
