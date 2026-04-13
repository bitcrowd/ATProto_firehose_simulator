# FirehoseSimulator

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`


The firehose simulator will start on [`localhost:4000`](http://localhost:4000).

The PLC stub will start on [`localhost:4001`](http://localhost:4001).

The PDS stub will start on [`localhost:4002`](http://localhost:4002).

Now you can visit [`localhost:4000`](http://localhost:4000) to control the firehose simulator.

## With Bluesky dataplane

```bash
cd dataplane
npm install
npm start
```

## Run simulation from IEx

Start the server in IEx:

```bash
iex -S mix phx.server
```

Metrics are exposed for Prometheus at `http://localhost:9568/metrics` and can be visualized in Grafana using the dashboard assets under `infra/`.

```bash
cd infra
docker compose up
```

Grafana is available at `http:localhost:3000`.

Import [`infra/firesim-1775727593906.json`](/Users/joel/code/sim2/infra/firesim-1775727593906.json) through Grafana's dashboard import UI and map the `DS_PROMETHEUS` input to your local Prometheus datasource.

## Web UI

1. `Setup`: create the userbase or import one using the configured database.
2. `Planning`: generate plans from params JSON or import plans from scenario JSON files.
3. `Simulation`: select one available plan and play/stop/reset.
4. `Vacuum`: run cleanup actions for userbase and/or post tables.

## In IEx

Create your userbase from a userbase JSON file:

```elixir
userbase_path = "priv/simulation/userbase.json"
{:ok, _result} = FirehoseSimulator.create_userbase(userbase_path)
```

 Generate a scenario from params JSON:

```elixir
{:ok, scenario} =
  FirehoseSimulator.generate_scenario_from_json(
    scenario_params: "priv/simulation/scenario_params.json"
  )
```


Play the plan:

```elixir
{:ok, player_id, _result} = FirehoseSimulator.play(scenario)
```

You can play multiple plans at the same time: 
```elixir
{:ok, player_id_2, _result} = FirehoseSimulator.play(scenario)
```

Stop and reset a specific player:

```elixir
:ok = FirehoseSimulator.stop(player_id)
:ok = FirehoseSimulator.reset(player_id)
```

Stop/reset all running players:

```elixir
:ok = FirehoseSimulator.stop_all()
:ok = FirehoseSimulator.reset_all()
```
Use vacuum functions to truncate userbase and/or post tables:

```elixir
{:ok, _result} = FirehoseSimulator.vacuum(delete_userbase?: true, delete_posts?: true)
```

### Userbase

Export a userbase to CSV files plus a manifest:

```elixir
userbase_path = "priv/simulation/bluesky_userbase.json"
{:ok, export_result} = FirehoseSimulator.export_userbase_to_csv(userbase_path, "priv/userbases")
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
    scenario_params: "priv/simulation/scenario_params.json"
  )

shifted_scenario = FirehoseSimulator.shift_scenario(scenario, 5_000)
{:ok, _player_id, _result} = FirehoseSimulator.play(shifted_scenario)
```

Export and re-import full scenario as JSON:

```elixir
:ok =
  FirehoseSimulator.export_scenario_to_json(scenario, "scenario.json")

{:ok, imported_plan} =
  FirehoseSimulator.import_scenario_from_json("scenario.json")
```
