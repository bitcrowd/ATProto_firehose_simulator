# Simulation Plans

## Purpose

Simulation plans define timed events for posts, follows, and sessions. Plans can be generated from parameter JSON or imported/exported as full plan JSON.

## Modules

- `FirehoseSimulator.SimulationPlan`
- `FirehoseSimulator.SimulationPlan.Params.SimulationPlanParams`
- `FirehoseSimulator.SimulationPlan.Params.PostsParams`
- `FirehoseSimulator.SimulationPlan.Params.FollowsParams`
- `FirehoseSimulator.SimulationPlan.Params.SessionsParams`
- `FirehoseSimulator.SimulationPlan.Params.PostTier`
- `FirehoseSimulator.SimulationPlan.Params.FollowTier`
- `FirehoseSimulator.SimulationPlan.Params.SessionTier`
- `FirehoseSimulator.SimulationPlan.Posts`
- `FirehoseSimulator.SimulationPlan.Follows`
- `FirehoseSimulator.SimulationPlan.Sessions`
- `FirehoseSimulator.SimulationPlan.JSON`
- `FirehoseSimulator.SimulationPlan.JsonEmbeddedLoader`
- Top-level orchestration in `FirehoseSimulator`

## Public Entry Points

- `FirehoseSimulator.generate_simulation_plan_from_json/1`
- `FirehoseSimulator.generate_simulation_plan_from_json/1` (keyword opts form)
- `FirehoseSimulator.import_simulation_plan_from_json/1`
- `FirehoseSimulator.export_simulation_plan_to_json/2`
- `FirehoseSimulator.SimulationPlan.generate_from_json/1`
- `FirehoseSimulator.SimulationPlan.from_json_file/1`
- `FirehoseSimulator.SimulationPlan.to_json/1`

## Parameters

### Top-Level Plan Params

`SimulationPlanParams` supports:

- `time_unit_duration_ms` (optional, integer > 0, default `86_400_000`)
- `posts_params` (optional)
- `sessions_params` (optional)
- `follows_params` (optional)

### Shared Section Params

`PostsParams`, `FollowsParams`, and `SessionsParams` each validate:

- `n` (required, integer > 0)
- `max_active_user_id` (required, integer > 0)
- `follower_density` (optional, float > 0, default `1.0`)
- `seed` (required integer)
- `time_units` (required, integer > 0)
- `tiers` (required, at least one tier)

`SessionsParams` also validates:

- `request_interval_ms` (optional, integer > 0, default `30_000`)

### Generation Options

`FirehoseSimulator.SimulationPlan.generate_from_json/1` accepts:

- string path shorthand
- keyword options with `:simulation_plan_params` or `:params`

## Runtime Behavior

1. Parameter JSON is loaded and validated by embedded schemas.
2. Optional sections (`posts_params`, `sessions_params`, `follows_params`) are generated independently.
3. `Posts.generate/2`, `Sessions.generate/2`, and `Follows.generate/2` produce event lists with `offset_ms`-based scheduling.
4. `request_interval_ms` is derived from `sessions_params` when present, else defaulted.
5. The result is returned as `%FirehoseSimulator.SimulationPlan{posts, sessions, follows, request_interval_ms}`.
6. Full plans can be encoded/decoded via `SimulationPlan.JSON` and file I/O wrappers.

## Failure Modes

- Invalid params JSON returns schema validation errors.
- Missing params/plan files return readable `{:error, ...}` tuples.
- JSON encode/decode failures return `{:error, reason}`.
