# FirehoseSimulator

This project simulates incoming traffic and user requests for an atproto dataplane such as the one used by bluesky.

![Overview of simulator](docs/overview.svg)

Here is brief [overview](docs/overview.md) document that describes the functionality of the simulator.

The project is set up to work with two variants of the dataplane:

1. Bluesky's [open source dataplane](./dataplane) which is based on Node and Postgres
2. An [Elixir implementation](https://github.com/bitcrowd/dataplane_elixir/) that stores data in ETS

## Getting Started

Install Elixir 1.20 and Erlang 28, for instance with [mise](https://mise.jdx.dev/), and make sure Docker is running.

Run the simulator, along with all dependent services with:

```bash
script/start
```

The first run copies `.env.example` to `.env`, starts the dependent services (Postgres, the dataplane, Prometheus and Grafana) in Docker,
then starts the simulator on your machine in an IEx session. Stop the simulator with `Ctrl-C`, then run `script/stop` to stop the services.

By default the dataplane is the Elixir (ETS) implementation. To run with the Node dataplane instead, pass `node`:

```bash
script/start node
```

Then open:

- Web UI / firehose: [`localhost:4000`](http://localhost:4000)
- Grafana: [`localhost:3000`](http://localhost:3000) (user: `admin` / password: `admin`)

Open a shell in the running dataplane container (Elixir or Node) with `script/shell`.

Example [userbase](example/userbase.json) and [scenario params](example/scenario_params.json) are available.

## Configuration

Runtime configuration is loaded from environment variables using [Dotenvy](https://hexdocs.pm/dotenvy) in `config/runtime.exs`. Copy the existing template and edit it:

```bash
cp .env.example .env
```

For more details about specific configuration options read [configuration-and-files](docs/configuration-and-files.md).

## Loading data into the dataplane

The Elixir dataplane can be seeded with users and follows from CSV files. Load users before follows, since follows reference existing users. See [dataplane_elixir](https://github.com/bitcrowd/dataplane_elixir#loading-users-and-follows) for the expected CSV columns.

The dataplane runs as a release in Docker, so copy the CSV files into the container and attach a remote console:

```bash
docker compose cp users.csv dataplane-elixir:/tmp/users.csv
docker compose cp follows.csv dataplane-elixir:/tmp/follows.csv
docker compose exec dataplane-elixir bin/dataplane_ex remote
```

Then load the data:

```elixir
alias DataplaneEx.Indexer

Indexer.bulk_users_from_file("/tmp/users.csv")
Indexer.bulk_follows_from_file("/tmp/follows.csv")
```

Delete all loaded data with `Indexer.vacuum()`.

## Metrics

Metrics are exposed for Prometheus at `http://localhost:9568/metrics`. Read [metrics](docs/metrics.md) for a description of the metrics.

Grafana is available at [`localhost:3000`](http://localhost:3000). It already has Prometheus configured as a data source. To load the dashboard, import [`infra/simulator.json`](infra/simulator.json) through Grafana's dashboard import UI and, when prompted for the `DS_PROMETHEUS` input, select the existing Prometheus data source.

## Web UI

1. `Setup`: create the userbase or import one using the configured database (only for the Node dataplane).
2. `Planning`: generate scenarios from params JSON, import scenarios, or import a simulation plan JSON file.
3. `Simulation`: select one available scenario and play/stop while building up the active simulation plan.
4. `Metrics`: a summary of the most important metrics, use Grafana for better insights.
5. `Vacuum`: run cleanup actions for userbase and/or post tables.

## In IEx

Create your userbase from a userbase JSON file (only for the Node dataplane, see `Loading data into the dataplane` for instructions for the Elixir dataplane):

```elixir
userbase_path = "example/userbase.json"
{:ok, _result} = FirehoseSimulator.create_userbase(userbase_path)
```

Generate a scenario from params JSON:

```elixir
{:ok, scenario} = FirehoseSimulator.generate_scenario_from_json("example/scenario_params.json")
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
{:ok, scenario} = FirehoseSimulator.generate_scenario_from_json("example/scenario_params.json")

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
