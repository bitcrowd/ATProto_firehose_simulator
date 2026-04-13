# Scenarios

## Purpose

Scenarios define timed events for posts, follows, and sessions. Plans can be generated from parameter JSON or imported/exported as full plan JSON.

## Modules

- `FirehoseSimulator.Scenario`
- `FirehoseSimulator.Scenario.Params.ScenarioParams`
- `FirehoseSimulator.Scenario.Params.PostsParams`
- `FirehoseSimulator.Scenario.Params.FollowsParams`
- `FirehoseSimulator.Scenario.Params.SessionsParams`
- `FirehoseSimulator.Scenario.Params.PostTier`
- `FirehoseSimulator.Scenario.Params.FollowTier`
- `FirehoseSimulator.Scenario.Params.SessionTier`
- `FirehoseSimulator.Scenario.Posts`
- `FirehoseSimulator.Scenario.Follows`
- `FirehoseSimulator.Scenario.Sessions`
- `FirehoseSimulator.Scenario.JSON`
- `FirehoseSimulator.Scenario.JsonEmbeddedLoader`
- Top-level orchestration in `FirehoseSimulator`

## Public Entry Points

- `FirehoseSimulator.generate_scenario_from_json/1`
- `FirehoseSimulator.generate_scenario_from_json/1` (keyword opts form)
- `FirehoseSimulator.import_scenario_from_json/1`
- `FirehoseSimulator.export_scenario_to_json/2`
- `FirehoseSimulator.Scenario.generate_from_json/1`
- `FirehoseSimulator.Scenario.from_json_file/1`
- `FirehoseSimulator.Scenario.to_json/1`

## Parameters

### Top-Level Plan Params

`ScenarioParams` supports:

- `time_unit_duration_ms` (optional, integer > 0, default `86_400_000`)
- `posts_params` (optional)
- `sessions_params` (optional)
- `follows_params` (optional)

### Shared Section Params

`PostsParams`, `FollowsParams`, and `SessionsParams` each validate:

- `num_users` (required, integer > 0)
- `max_active_user_id` (required, integer > 0)
- `follower_density` (optional, float > 0, default `1.0`)
- `seed` (required integer)
- `time_units` (required, integer > 0)
- `tiers` (required, at least one tier)

`SessionsParams` also validates:

- `request_interval_ms` (optional, integer > 0, default `30_000`)

### Generation Options

`FirehoseSimulator.Scenario.generate_from_json/1` accepts:

- string path shorthand
- keyword options with `:scenario_params` or `:params`

## Runtime Behavior

1. Parameter JSON is loaded and validated by embedded schemas.
2. Optional sections (`posts_params`, `sessions_params`, `follows_params`) are generated independently.
3. `Posts.generate/2`, `Sessions.generate/2`, and `Follows.generate/2` produce event lists with `offset_ms`-based scheduling.
4. `request_interval_ms` is derived from `sessions_params` when present, else defaulted.
5. The result is returned as `%FirehoseSimulator.Scenario{posts, sessions, follows, request_interval_ms}`.
6. Full plans can be encoded/decoded via `Scenario.JSON` and file I/O wrappers.

## Failure Modes

- Invalid params JSON returns schema validation errors.
- Missing params/plan files return readable `{:error, ...}` tuples.
- JSON encode/decode failures return `{:error, reason}`.
