# FirehoseSimulator

This project is a simulates incoming traffic and user requests for an atproto dataplane such as the one used by bluesky.

![Overview of simulator](docs/overview.svg)

Here is brief [overview](docs/overview.md) document that describes the functionality of the simulator.

## Getting Started

Install Elixir 1.19 and Erlang 28, for instance with [mise](https://mise.jdx.dev/).

For configuration options read [configuration-and-files](docs/configuration-and-files.md).

A small starter script for the open source implementation of the Bluesky dataplane is available.

The dataplane needs a Postgres database.
You can create the default one with:

```bash
createdb -U postgres -p 5432 dataplane
```

Starting the dataplane will run the required migrations.

Set up the environment.

```bash
export BSKY_DB_POSTGRES_URL=postgres://postgres:postgres@localhost:5432/dataplane
export BSKY_DB_POSTGRES_SCHEMA=bsky
export BSKY_DATAPLANE_PORT=2585
export BSKY_DID_PLC_URL=http://localhost:4001
export BSKY_RELAY_WEBSOCKET=ws://localhost:4000
```

Then start the dataplane.

```bash
cd dataplane

npm install

NODE_ENV=production npm start
```

To start the simulator, install and setup dependencies.

```bash
MIX_ENV=prod mix setup
```

Set up the environment for the simulator.

```bash
export DATABASE_URL=postgres://postgres:postgres@localhost:5432/dataplane
export DATAPLANE_URL=http://localhost:2585
export PLC_MULTIKEY=zQ3shaSUSFjTPxogQR7eQ9QGwKWUdMmrHyjNiUg9oGJ8Lefiv
export PLC_PRIVATE_HEX=bfe084f28e8bd6a64cbc18eea04c17457c9c48ce34498bc635b19ec7530d5e4a
export PORT=4000
export PLC_PORT=4001
export PDS_PORT=4002
export FINCH_POOL_SIZE=200
export PROMETHEUS_PORT=9568
export USERBASE_JSON=example/userbase.json
```

Then start the simulator.

```bash
MIX_ENV=prod iex -S mix phx.server
```

The firehose simulator will start on [`localhost:4000`](http://localhost:4000).

The PLC stub will start on [`localhost:4001`](http://localhost:4001).

The PDS stub will start on [`localhost:4002`](http://localhost:4002).

Now you can visit [`localhost:4000`](http://localhost:4000) to control the firehose simulator or work from IEx.

Example [userbase](example/userbase.json) and [scenario params](example/scenario_params.json) are available.

## Metrics

Metrics are exposed for Prometheus at `http://localhost:9568/metrics` and can be visualized in Grafana using the dashboard assets under `infra/`.

Read [metrics](docs/metrics.md) for a description of the metrics. 

```bash
cd infra
docker compose up
```

Grafana is available at `http:localhost:3000`.

Import [`infra/simulator.json`](infra/simulator.json) through Grafana's dashboard import UI and map the `DS_PROMETHEUS` input to your local Prometheus datasource.

## Web UI

1. `Setup`: create the userbase or import one using the configured database.
2. `Planning`: generate scenarios from params JSON, import scenarios, or import a simulation plan JSON file.
3. `Simulation`: select one available scenario and play/stop while building up the active simulation plan.
4. `Metrics`: a summary of the most important metrics, use Grafana for better insights.
5. `Vacuum`: run cleanup actions for userbase and/or post tables.

## In IEx

Create your userbase from a userbase JSON file:

```elixir
userbase_path = "example/userbase.json"
{:ok, _result} = FirehoseSimulator.create_userbase(userbase_path)
```

 Generate a scenario from params JSON:

```elixir
{:ok, scenario} =
  FirehoseSimulator.generate_scenario_from_json(
    scenario_params: "example/scenario_params.json"
  )
```

Play the scenario:

```elixir
{:ok, player_id, _result} = FirehoseSimulator.load(scenario)
:ok = FirehoseSimulator.start(player_id)
```

You can play multiple scenarios at the same time: 
```elixir
{:ok, player_id_2, _result} = FirehoseSimulator.load(scenario)
:ok = FirehoseSimulator.start(player_id_2)
```

Stop a specific player:

```elixir
:ok = FirehoseSimulator.stop(player_id)
```

Stop all running players:

```elixir
:ok = FirehoseSimulator.stop()
```

Use vacuum functions to truncate userbase and/or post tables:

```elixir
{:ok, _result} = FirehoseSimulator.vacuum(delete_userbase?: true, delete_posts?: true)
```

### Userbase

Export a userbase to CSV files plus a manifest:

```elixir
userbase_path = "example/userbase.json"
{:ok, export_result} = FirehoseSimulator.export_userbase_to_csv(userbase_path, "example/userbases")
```

Import that exported userbase into Postgres with `COPY`:

```elixir
meta_path = export_result.meta_path
{:ok, _result} = FirehoseSimulator.import_userbase_from_csv(meta_path)
```

The import path uses server-side `COPY FROM '/absolute/path.csv'`, so the Postgres server process must be able to read the exported CSV files.


### Scenarios

Shift an in-memory scenario by a millisecond offset:

```elixir
{:ok, scenario} =
  FirehoseSimulator.generate_scenario_from_json(
    scenario_params: "example/scenario_params.json"
  )

shifted_scenario = FirehoseSimulator.shift_scenario(scenario, 5_000)
{:ok, shifted_player_id, _result} = FirehoseSimulator.load(shifted_scenario)
:ok = FirehoseSimulator.start(shifted_player_id)
```

Export and re-import full scenario as JSON:

```elixir
:ok =
  FirehoseSimulator.export_scenario_to_json(scenario, "scenario.json")

{:ok, imported_plan} =
  FirehoseSimulator.import_scenario_from_json("scenario.json")
```

### Simulation Plans

Add a scenario to the active simulation plan and export the updated plan snapshot:

```elixir
{:ok, scenario} =
  FirehoseSimulator.import_scenario_from_json("scenario.json")

{:ok, simulation_plan} =
  FirehoseSimulator.add_and_play_scenario(
    "baseline",
    scenario,
    0,
    "scenario.json"
  )
```

Export the current plan:

```elixir
:ok =
  FirehoseSimulator.export_simulation_plan_to_json(
    FirehoseSimulator.current_simulation_plan(),
    "simulation_plan.json"
  )
```

Import a saved simulation plan:

```elixir
{:ok, simulation_plan} =
  FirehoseSimulator.import_simulation_plan_from_json("simulation_plan.json")
```

Simulation-plan JSON references scenario JSON files by path. Relative paths are resolved relative to the plan file during import.
