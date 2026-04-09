# Base Data

## Purpose

Base data defines the initial simulated population used by both bulk creation and live playback workflows.

## Modules

- `FirehoseSimulator.SimulationPlan.Userbase`
- `FirehoseSimulator`
- `FirehoseSimulator.BulkCreation`
- `FirehoseSimulator.SimulationPlan.FollowerGraph`

## Public Entry Points

- `FirehoseSimulator.create_userbase/0`
- `FirehoseSimulator.create_userbase/1`
- `FirehoseSimulator.create_userbase/2`
- `FirehoseSimulator.SimulationPlan.Userbase.load_file/1`

## Parameters

### Userbase JSON

`FirehoseSimulator.SimulationPlan.Userbase` validates:

- `name` (required, non-empty string)
- `num_users` (required, integer > 0)
- `max_active_user_id` (required, integer > 0 and `<= num_users`)
- `follower_density` (optional, float > 0, default `1.0`)

### Connection Input

`create_userbase/2` accepts either:

- `%FirehoseSimulator.DatabaseConnection{connection_string: ...}`
- a Postgres connection string (wrapped into `DatabaseConnection` internally)

## Runtime Behavior

1. `FirehoseSimulator.create_userbase/*` resolves userbase path and DB connection.
2. `Userbase.load_file/1` reads and validates JSON via embedded changesets.
3. `BulkCreation.create_userbase/2` connects through `BulkCreation.DynamicRepo`.
4. `FollowerGraph.generate/2` builds the follower relationships from `num_users` and `follower_density`.
5. Bulk insertions write actors and follows with deterministic offsets.
6. The function returns counts (`inserted_actor_count`, `inserted_follow_count`) and user ID range metadata.

## Failure Modes

- Missing/unreadable userbase file returns `{:error, "cannot read userbase file at ..."}`.
- Invalid userbase fields return validation errors.
- Non-Postgres connection strings return `{:error, "Connection string must be a postgres URL"}`.
- DB connection or insert failures bubble up as `{:error, reason}`.
