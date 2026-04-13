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

## With ATProto dev-env

1. Clone the repo

```bash
git clone https://github.com/bluesky-social/atproto
```

2. Apply the patch that set's the firehose port to `4000`, while keeping the remaining setup

```bash
git apply firehose.patch
```

3. Follow the setup as described here: https://github.com/bluesky-social/atproto/blob/main/README.md#developer-quickstart

You can run `make run-dev-env-logged` to see logs.

The introspection is available at [`localhost:2581`](http://localhost:2581). 

The postgres database at `postgresql://pg:password@127.0.0.1:5433/postgres`.

## With Blacksky

1. Clone the repo

```bash
git clone https://github.com/blacksky-algorithms/atproto
```

2. Patch

The pnpm lockfile needs version > 9 but is locked to > 8, so we patch to remove the pnpm lock.

```bash
(cd <blacksky-algorithms/atproto_path> && git apply <simulator_path>/atproto_blacksky.patch)
```

3. Set up environment

```bash
export DB_PRIMARY_URL="postgres://postgres:postgres@localhost:5432/atproto_blacksky?options=-csearch_path%3Dbsky"
export BSKY_DB_POSTGRES_URL="postgres://postgres:postgres@localhost:5432/atproto_blacksky?options=-csearch_path%3Dbsky"
export BSKY_DATAPLANE_URLS="http://localhost:2585"
export BSKY_DID="did:web:api.example.com"
export BSKY_MOD_SERVICE_DID="did:web:ozone.example.com"
export MOD_SERVICE_DID="did:web:ozone.example.com"
export BSKY_ADMIN_PASSWORDS="admin"
export BSKY_BSYNC_URL="http://localhost:3000"
export CLUSTER_WORKER_COUNT=1
```

For development, there is a default PLC multikey configured (same key will be used for everything).

If you want, you can generate a new keypair:

```bash
mix run -e 'IO.inspect(PLC.Keys.generate(), pretty: true)'

export PLC_MULTIKEY=<multikey>
```

You must set the `private_hex` for `BSKY_SERVICE_SIGNING` accordingly.


4. Follow [instructions](https://github.com/blacksky-algorithms/atproto/?tab=readme-ov-file#setup) to run dataplane and AppView

```bash
pnpm install
pnpm build
```

```bash
node services/bsky/dataplane.js
```

Use the private_hex value you generated for `BSKY_SERVICE_SIGNING_KEY` if you set a different key for the PLC in step 3.

```bash
BSKY_SERVICE_SIGNING_KEY=bfe084f28e8bd6a64cbc18eea04c17457c9c48ce34498bc635b19ec7530d5e4a node services/bsky/api.js
```

5. Clone rsky to run wintermute

```bash
git clone https://github.com/blacksky-algorithms/rsky/
```

6. Patch wintermute

This patch makes wintermute subscribe to the websocket via `ws://` instead of `wss://`.

```bash
(cd <blacksky-algorithms/rsky_path> && git apply <simulator_path>/wintermute.patch)
```

6. Set environment
```bash
export RELAY_HOSTS="http://localhost:4000" # to firehose simulator 
export DATABASE_URL="postgres://postgres:postgres@localhost:5432/atproto_blacksky?options=-csearch_path%3Dbsky" # according to step 2 
export RUST_LOG=debug
```

7. We must fix the DB schema to expected format

```bash
psql $DATABASE_URL -c "CREATE TABLE IF NOT EXISTS bsky.sub_state (service varchar NOT NULL PRIMARY KEY, cursor bigint NOT NULL);"
psql $DATABASE_URL -c "ALTER TABLE bsky.record ADD COLUMN IF NOT EXISTS rev text;"
```

8. Follow [instructions for running wintermute](https://github.com/blacksky-algorithms/rsky/blob/main/rsky-wintermute/README.md)


```bash
cargo build --release --package rsky-wintermute

./target/release/wintermute
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

## Web UI

1. `Setup`: configure database connection and create the userbase.
2. `Planning`: generate plans from params JSON or import plans from scenario JSON files.
3. `Simulation`: select one available plan and play/stop/reset.
4. `Vacuum`: run cleanup actions for userbase and/or post tables.


## In IEx

Create your userbase with a DB connection string and userbase JSON file:

```elixir
db_url = "postgres://postgres:postgres@localhost:5432/dataplane"
userbase_path = "priv/simulation/userbase.json"
{:ok, _result} = FirehoseSimulator.create_userbase(userbase_path, db_url)
```

 Generate a scenario from params JSON:

`scenario_params.json` supports an optional top-level `time_unit_duration_ms` field. If omitted, one time unit defaults to `86_400_000` ms (24 hours).
Within `sessions_params`, `request_interval_ms` controls timeline request cadence for all sessions in the generated plan and defaults to `30_000` ms.

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
{:ok, _result} = FirehoseSimulator.vacuum(db_url, delete_userbase?: true, delete_posts?: true)
```

### Userbase

Export a userbase to CSV files plus a manifest:

```elixir
userbase_path = "priv/simulation/bluesky_userbase.json"
{:ok, export_result} = FirehoseSimulator.export_userbase_to_csv(userbase_path, "priv/userbases")
```

Import that exported userbase into Postgres with `COPY`:

```elixir
db_url = "postgres://postgres:postgres@localhost:5432/dataplane"
meta_path = export_result.meta_path
{:ok, _result} = FirehoseSimulator.import_userbase_from_csv(meta_path, db_url)
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
