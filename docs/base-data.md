# Base Data

## Purpose

Base data defines the initial simulated population used by both bulk creation and live playback workflows.

## Modules

- `FirehoseSimulator`
- `FirehoseSimulator.BulkCreation`
- `FirehoseSimulator.Scenario.FollowerGraph`

## Public Entry Points

- `FirehoseSimulator.create_userbase/0`
- `FirehoseSimulator.create_userbase/1`
- `FirehoseSimulator.export_userbase_to_csv/1,2,3`
- `FirehoseSimulator.import_userbase_from_csv/1`

## Parameters

### Userbase JSON

`FirehoseSimulator.BaseData.Userbase` validates:

- `name` (required, non-empty string)
- `num_users` (required, integer > 0)
- `max_active_user_id` (required, integer > 0 and `<= num_users`)
- `follower_density` (optional, float > 0, default `1.0`)

### Database Configuration

`create_userbase/*` and `import_userbase_from_csv/1` use the application repo, `FirehoseSimulator.Repo`.

Configure the DB URL once at startup:

- `config/dev.exs` in development
- `config/test.exs` in test
- `config/runtime.exs` in production

### CSV Export Inputs

- `export_userbase_to_csv/1` exports into `priv/userbases`
- `export_userbase_to_csv/2` accepts an export directory
- `export_userbase_to_csv/3` accepts an export directory plus options such as `:run_id`

## Runtime Behavior

1. `FirehoseSimulator.create_userbase/*` resolves the userbase path.
2. `Userbase.load_file/1` reads and validates JSON via embedded changesets.
3. `BulkCreation.create_userbase/1` writes through `FirehoseSimulator.Repo`.
4. `FollowerGraph.generate/2` builds the follower relationships from `num_users` and `follower_density`.
5. Direct bulk insertion writes actors and follows with deterministic offsets.
6. `export_userbase_to_csv/*` generates actor/follow rows in memory, writes `actor.csv` and `follow.csv`, then writes `userbase_meta.json`.
7. `import_userbase_from_csv/1` loads `userbase_meta.json` and runs server-side `COPY` for actors first, then follows.
8. Each function returns counts plus file path metadata where applicable.

### Manifest Format

The CSV workflow writes a `userbase_meta.json` manifest containing:

- `version`
- `kind`
- `run_id`
- `exported_at`
- `userbase`
- `files.actor.path`
- `files.actor.row_count`
- `files.follow.path`
- `files.follow.row_count`

CSV paths in the manifest are absolute paths.

## Failure Modes

- Missing/unreadable userbase file returns `{:error, "cannot read userbase file at ..."}`.
- Invalid userbase fields return validation errors.
- DB connection or insert failures bubble up as `{:error, reason}`.
- Missing or invalid manifest files return `{:error, ...}` from `UserbaseMeta`.
- CSV import fails if Postgres cannot read the absolute CSV paths referenced by the manifest.
