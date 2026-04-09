# Bulk Creation

## Purpose

Bulk creation materializes simulation data directly in Postgres without requiring live playback.

## Modules

- `FirehoseSimulator.BulkCreation`
- `FirehoseSimulator.BulkCreation.DynamicRepo`
- `FirehoseSimulator.BulkCreation.Actor`
- `FirehoseSimulator.BulkCreation.Follow`
- `FirehoseSimulator.BulkCreation.Post`
- `FirehoseSimulator.BulkCreation.Record`
- `FirehoseSimulator.BulkCreation.FeedItem`
- `FirehoseSimulator.BulkCreation.Vacuum`
- `FirehoseSimulator.Data`

## Public Entry Points

- `FirehoseSimulator.bulk_create_simulation_plan/1`
- `FirehoseSimulator.bulk_create_simulation_plan/2`
- `FirehoseSimulator.create_userbase/0,1,2`
- `FirehoseSimulator.vacuum/0,1,2`
- `FirehoseSimulator.BulkCreation.create_simulation_plan/2`
- `FirehoseSimulator.BulkCreation.create_userbase/2`

## Parameters

### Required Inputs

- `%FirehoseSimulator.SimulationPlan{}` for simulation-plan bulk loads.
- `%FirehoseSimulator.SimulationPlan.Userbase{}` for userbase-only loads.
- `%FirehoseSimulator.DatabaseConnection{connection_string: ...}` (or string wrapper via top-level API).

### Connection Constraints

- Connection string must start with `postgres://` or `postgresql://`.

### Insert Behavior

- Inserts are batched (`@insert_batch_size` in `BulkCreation`).
- `on_conflict: :nothing` is used for key tables to avoid duplicate-key failures on replays.

## Runtime Behavior

1. `BulkCreation.connect/1` validates connection string and starts a dynamic repo.
2. For plan bulk loads:
- posts/follows/sessions are extracted from the plan (`nil` sections become empty lists).
- actor IDs are inferred from event payloads and deduplicated.
- actor rows are inserted first.
- post rows produce correlated post/record/feed_item rows.
- follows are inserted after actors.
3. For userbase bulk loads:
- follower graph is generated from base-data params.
- actor rows and follow rows are inserted.
4. `vacuum/*` delegates to `BulkCreation.Vacuum.run/2` and logs results.

## Return Values

Bulk operations return summary maps, including counts such as:

- `inserted_actor_count`
- `inserted_follow_count`
- `inserted_post_count`
- `inserted_record_count`
- `inserted_feed_item_count`
- `included_session_count`

## Failure Modes

- Invalid connection string format returns `{:error, ...}`.
- Repo connect failures return `{:error, ...}`.
- DB write errors return `{:error, reason}` from insertion steps.
