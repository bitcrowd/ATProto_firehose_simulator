# Examples

| Path | What it is |
|---|---|
| [`userbase.json`](userbase.json) | Userbase with 1000 users |
| [`scenario_params.json`](scenario_params.json) | Scenario params for the 1000 user userbase: one 20 minute time unit with posts, sessions and follows |
| [`userbases/`](userbases) | The 1000 user userbase exported to CSV, for loading into the Elixir dataplane |
| [`small/`](small) | A small, fast setup for trying things out and for demos (see below) |

## Small example

`small/` contains a 100 user userbase and two scenarios that are meant to be played together:

| Path | What it is |
|---|---|
| `small/userbase.json` | Userbase with 100 users |
| `small/users.csv`, `small/follows.csv` | The same userbase exported to CSV (100 users, 416 follows), for the Elixir dataplane |
| `small/params/quiet.json` | Params for a 4 minute baseline: about 100 posts, 40 follows, every user online for a minute every 2 minutes, refreshing their timeline every 10 seconds |
| `small/params/spike.json` | Params for a 1 minute spike: about 380 posts, 140 follows, all users online at once, refreshing their timeline every 2 seconds |
| `small/scenarios/` | The scenarios generated from those params |
| `small/simulation_plan.json` | Plays `quiet` and starts `spike` 90 seconds in |

### Load the userbase

Elixir dataplane (the default of `script/start`):

```bash
docker compose cp example/small/users.csv dataplane-elixir:/tmp/users.csv
docker compose cp example/small/follows.csv dataplane-elixir:/tmp/follows.csv
docker compose exec dataplane-elixir bin/dataplane_ex rpc '
  DataplaneEx.Indexer.bulk_users_from_file("/tmp/users.csv")
  DataplaneEx.Indexer.bulk_follows_from_file("/tmp/follows.csv")'
```

Node dataplane (`script/start node`), in IEx:

```elixir
{:ok, _} = FirehoseSimulator.create_userbase("example/small/userbase.json")
```

### Play it

In IEx, import the simulation plan and start its players:

```elixir
{:ok, _plan} = FirehoseSimulator.import_simulation_plan_from_json("example/small/simulation_plan.json")

FirehoseSimulator.State.list_players()
|> Map.keys()
|> Enum.each(&FirehoseSimulator.start/1)
```

Or in the web UI: in `Planning`, generate a scenario from `small/params/quiet.json` and one from `small/params/spike.json`. In `Simulation`, load `quiet` with offset `0` and `spike` with offset `90000`, then play both.

Stop everything with `FirehoseSimulator.stop()`.

## Writing your own

The userbase and the scenario params work together, so a few things need to match.

**Userbase.** `num_users` users with IDs `1..num_users` get a power law follower graph: user `n` has about `num_users / n * follower_density - 1` followers, so user 1 is followed by everyone and the last users by no one. See `FirehoseSimulator.BaseData.FollowerGraph`.

**Scenario params.** `posts_params`, `sessions_params` and `follows_params` each describe one kind of activity:

- `num_users` and `follower_density` must match the userbase, since they are used to compute each user's follower count.
- Users `1..max_active_user_id` take part, the rest stay idle. Lower IDs are the users with the most followers.
- Each active user gets the first tier whose `max_followers` is at least their follower count, or the last tier otherwise.
- A scenario runs for `time_units` units of `time_unit_duration_ms` each. Tier rates such as `posts_per_time_unit` are per user per unit.
- Every active user gets one session per unit, starting at a random time within that unit. If a session is as long as the unit or longer, all sessions start together at the beginning of the unit.

See [configuration and files](../docs/configuration-and-files.md) for all fields.

**Regenerating.** In IEx, export a userbase to CSV for the Elixir dataplane (the export writes `actor.csv` and `follow.csv`), and generate and save scenarios from params:

```elixir
FirehoseSimulator.export_userbase_to_csv("example/small/userbase.json", "/tmp/small_userbase")

{:ok, scenario} = FirehoseSimulator.generate_scenario_from_json("example/small/params/spike.json")
:ok = FirehoseSimulator.export_scenario_to_json(scenario, "example/small/scenarios/spike.json")
```

Scenario generation is deterministic for a given `seed`. Exporting a userbase always produces the same users and follow graph, but new timestamps and therefore new follow record CIDs.
