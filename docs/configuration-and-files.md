# Configuration and file formats

You must configure the environment for the simulator and dataplane to work correctly.

## Simulator env vars

| Env var           | Example value                                                      | Notes                                                                   |
|---                |---                                                                 |---                                                                      |
| `DATABASE_URL`    | `postgres://postgres:postgres@localhost:5432/dataplane`            | Simulator Postgres connection                                           |
| `DATAPLANE_URL`   | `http://localhost:2585`                                            | Base URL for requests to dataplane                                      |
| `PLC_MULTIKEY`    | `zQ3shaSUSFjTPxogQR7eQ9QGwKWUdMmrHyjNiUg9oGJ8Lefiv`                | PLC signing key material for the stub PLC service                       |
| `PLC_PRIVATE_HEX` | `bfe084f28e8bd6a64cbc18eea04c17457c9c48ce34498bc635b19ec7530d5e4a` | PLC private key hex for the stub PLC service, must match `PLC_MULTIKEY` |
| `PORT`            | `4000`                                                             | Main simulator HTTP port, this is the port that exposes the firehose    |
| `PLC_PORT`        | `4001`                                                             | Stub PLC HTTP port                                                      |
| `PDS_PORT`        | `4002`                                                             | Stub PDS HTTP port                                                      |
| `FINCH_POOL_SIZE` | `200`                                                              | Finch HTTP connection pool size used for dataplane requests             |
| `PROMETHEUS_PORT` | `9568`                                                             | Standalone metrics exporter port                                        |
| `USERBASE_JSON`   | `priv/simulation/userbase.json`                                    | Used as default path for userbase creation                              |

## Dataplane env vars

| Env var                   | Example value                                           | Notes                                                                     |
|---                        |---                                                      |---                                                                        |
| `BSKY_DB_POSTGRES_URL`    | `postgres://postgres:postgres@localhost:5432/dataplane` | Dataplane Postgres connection                                             |
| `BSKY_DB_POSTGRES_SCHEMA` | `bsky`                                                  | Target schema for dataplane tables                                        |
| `BSKY_DATAPLANE_PORT`     | `2585`                                                  | Dataplane HTTP port, must match `DATAPLANE_URL`                           |
| `BSKY_DID_PLC_URL`        | `http://localhost:4001`                                 | PLC service base URL used by the identity resolver, must match `PLC_PORT` |
| `BSKY_RELAY_WEBSOCKET`    | `ws://localhost:4000`                                   | Relay/firehose websocket URL, must match `PORT`                           |


## Elixir configuration

| Config key          | Notes                                      |
|---                  |---                                         |
| `:finch_pool_size`  | Finch HTTP connection pool size            |
| `:log_file_path`    | Runtime log file path                      |
| `:runs_root`        | Root directory for generated run artifacts |

## JSON configuration options

### Userbase JSON

These parameters are used to generate a userbase.

| Field                | Type    | Required | Default | Validation               |
|---                   |---      |---       |---      |---                       |
| `name`               | string  | yes      | none    | trimmed; min length 1    |
| `num_users`          | integer | yes      | none    | `> 0`                    |
| `max_active_user_id` | integer | yes      | none    | `> 0` and `<= num_users` |
| `follower_density`   | float   | no       | `1.0`   | `> 0`                    |

### Scenario params JSON

These parameters are used to generate a scenario.

Top-level fields:

| Field                   | Type    | Required | Default                                                              | Validation                    |
|---                      |---      |---       |---                                                                   |---                            |
| `seed`                  | integer | yes      | none                                                                 | integer                       |
| `time_units`            | integer | yes      | none                                                                 | `> 0`                         |
| `time_unit_duration_ms` | integer | no       | `nil` in schema; downstream code may apply its own effective default | `> 0` when present            |
| `posts_params`          | object  | no       | `nil`                                                                | validated by `PostsParams`    |
| `sessions_params`       | object  | no       | `nil`                                                                | validated by `SessionsParams` |
| `follows_params`        | object  | no       | `nil`                                                                | validated by `FollowsParams`  |

`posts_params`, `sessions_params`, and `follows_params` each carry their own configuration. Those fields are not top-level fields.

Fields in `posts_params`:

| Field                | Type    | Required | Default | Validation   |
|---                   |---      |---       |---      |---           |
| `num_users`          | integer | yes      | none    | `> 0`        |
| `max_active_user_id` | integer | yes      | none    | `> 0`        |
| `follower_density`   | float   | no       | `1.0`   | `> 0`        |
| `tiers`              | array   | yes      | none    | min length 1 |

Tier object fields:

| Tier block             | Field                 | Type    | Validation |
|---                     |---                    |---      |---         |
| `posts_params.tiers[]` | `max_followers`       | integer | `> 0`      |
| `posts_params.tiers[]` | `posts_per_time_unit` | float   | `>= 0`     |

Fields in `sessions_params`:

| Field                 | Type    | Required | Default  | Validation   |
|---                    |---      |---       |---       |---           |
| `request_interval_ms` | integer | no       | `30_000` | `> 0`        |
| `timeline_limit`      | integer | no       | `20`     | `> 0`        |
| `num_users`           | integer | yes      | none     | `> 0`        |
| `max_active_user_id`  | integer | yes      | none     | `> 0`        |
| `follower_density`    | float   | no       | `1.0`    | `> 0`        |
| `tiers`               | array   | yes      | none     | min length 1 |

Tier object fields:

| Tier block                | Field             | Type    | Validation |
|---                        |---                |---      |---         |
| `sessions_params.tiers[]` | `max_followers`   | integer | `> 0`      |
| `sessions_params.tiers[]` | `session_minutes` | integer | `> 0`      |

Fields in `follows_params`:

| Field                | Type    | Required | Default | Validation   |
|---                   |---      |---       |---      |---           |
| `num_users`          | integer | yes      | none    | `> 0`        |
| `max_active_user_id` | integer | yes      | none    | `> 0`        |
| `follower_density`   | float   | no       | `1.0`   | `> 0`        |
| `tiers`              | array   | yes      | none    | min length 1 |

Tier object fields:

| Tier block               | Field                   | Type    | Validation |
|---                       |---                      |---      |---         |
| `follows_params.tiers[]` | `max_followers`         | integer | `> 0`      |
| `follows_params.tiers[]` | `follows_per_time_unit` | float   | `>= 0`     |

### Scenario JSON

These files contain the data for a complete scenario.

Top-level fields:

| Field                 | Type            | Required | Default  | Validation                                                               |
|---                    |---              |---       |---       |---                                                                       |
| `posts`               | array or `null` | no       | `null`   | each item must contain integer `offset_ms` and `user_id`                 |
| `sessions`            | array or `null` | no       | `null`   | each item must contain integer `offset_ms`, `user_id`, and `duration_ms` |
| `follows`             | array or `null` | no       | `null`   | each item must contain integer `offset_ms`, `actor_id`, and `subject_id` |
| `request_interval_ms` | integer         | no       | `30_000` | `> 0`                                                                    |
| `timeline_limit`      | integer         | no       | `20`     | `> 0`                                                                    |

## Files and directories

The simulator reads input JSON from user-supplied paths, writes artifacts under a per-run directory, and also writes some files directly to caller-specified export paths.

### Default directories

| Path              | Purpose                          |
|---                |---                               |
| `runs/`           | Default root for run artifacts   |
| `log/`            | Log output directory             |

### Run artifact layout

On startup, the simulator creates a fresh run directory under `runs/` or the configured `:runs_root`.

The directory name format is:

- `YYYYMMDDTHHMMSSZ_<unique_integer>`

Within that run directory, the simulator may write:

| Relative path under run directory                | Purpose                                                    |
|---                                               |---                                                         |
| `userbase/userbase.json`                         | Snapshot of the userbase JSON used to create DB records    |
| `userbase/userbase_meta.json`                    | Snapshot of the imported CSV manifest                      |
| `scenario_params/<name>.json`                    | Copy of the scenario params JSON that generated a scenario |
| `scenarios/<name>.json`                          | Persisted scenario JSON used for replay/import/export      |
| `simulation_plan.json`                           | Persisted simulation-plan manifest                         |
| `artifacts/userbase/<run_id>/actor.csv`          | Exported actor CSV                                         |
| `artifacts/userbase/<run_id>/follow.csv`         | Exported follow CSV                                        |
| `artifacts/userbase/<run_id>/userbase_meta.json` | Manifest describing the CSV export                         |

### Logging

At application startup, file logging writes to a timestamped path derived from `:log_file_path`.

With the default config:

- configured base path: `log/firehose_simulator.log`
- actual file path format: `log/YYYYMMDDTHHMMSSZ_firehose_simulator.log`

### Userbase CSV export

| File                 | Format                       | Fields / contents                                               |
|---                   |---                           |---                                                              |
| `actor.csv`          | CSV, one actor row per line  | `did`, `indexedAt`, `trustedVerifier`                           |
| `follow.csv`         | CSV, one follow row per line | `uri`, `cid`, `creator`, `subjectDid`, `createdAt`, `indexedAt` |
| `userbase_meta.json` | JSON manifest                | export metadata plus absolute CSV paths and row counts          |

The export result also returns the paths and row counts.

### Userbase CSV manifest

`userbase_meta.json` fields:

| Field                         | Type    | Notes                             |
|---                            |---      |---                                |
| `version`                     | integer | Currently `1`                     |
| `kind`                        | string  | Currently `"userbase"`            |
| `run_id`                      | string  | Export run identifier             |
| `exported_at`                 | string  | ISO8601 timestamp                 |
| `userbase`                    | object  | Embedded source userbase settings |
| `userbase.name`               | string  | Userbase name                     |
| `userbase.num_users`          | integer | Number of users                   |
| `userbase.max_active_user_id` | integer | Highest active user id            |
| `userbase.follower_density`   | float   | Density used to generate follows  |
| `files`                       | object  | CSV file metadata                 |
| `files.actor.path`            | string  | Absolute path to `actor.csv`      |
| `files.actor.row_count`       | integer | Number of actor rows              |
| `files.follow.path`           | string  | Absolute path to `follow.csv`     |
| `files.follow.row_count`      | integer | Number of follow rows             |

The CSV paths in the manifest must be absolute paths, and the files must already exist when importing.

### Simulation Plan manifest

`simulation_plan.json` fields:

| Field                     | Type             | Notes                                                                                       |
|---                        |---               |---                                                                                          |
| `name`                    | string or `null` | Plan name                                                                                   |
| `entries`                 | array            | Ordered list of plan entries                                                                |
| `entries[].scenario_name` | string           | Display/name key for the scenario                                                           |
| `entries[].scenario_path` | string           | Path to a scenario JSON file; relative paths resolve from the plan file directory on import |
| `entries[].offset_ms`     | integer          | Offset applied when the scenario is loaded/imported                                         |
