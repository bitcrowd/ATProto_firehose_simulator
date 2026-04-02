# FirehoseSimulator

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`


The firehose simulator will start on [`localhost:4000`](http://localhost:4000).

The PLC stub will start on [`localhost:4001`](http://localhost:4001).

The PDS stub will start on [`localhost:4002`](http://localhost:4002).

Now you can visit [`localhost:4000`](http://localhost:4000) to control the firehose simulator.

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

In IEx, create your userbase with a DB connection string and userbase JSON file:

```elixir
db_url = "postgres://postgres:postgres@localhost:5432/atproto_blacksky?options=-csearch_path%3Dbsky"
userbase_path = "priv/simulation/userbase.json"
{:ok, _result} = FirehoseSimulator.create_userbase(userbase_path, db_url)
```

You can also run vacuum actions from IEx to either delete the full userbase footprint or vacuum posts:

```elixir
{:ok, _result} = FirehoseSimulator.vacuum(db_url, delete_userbase?: true)
{:ok, _result} = FirehoseSimulator.vacuum(db_url, vacuum_posts?: true)
```

Flow in the web UI:

1. `Setup`: configure database connection and create the userbase.
2. `Vacuum`: run delete userbase and/or vacuum posts actions.
3. `Planning`: generate plans from params JSON or import plans from simulation plan JSON files.
4. `Simulation`: select one available plan and play/stop/reset.

Generate a simulation plan from params JSON:

```elixir
{:ok, simulation_plan} =
  FirehoseSimulator.generate_simulation_plan_from_json(
    simulation_plan_params: "priv/simulation/simulation_plan_params.json"
  )
```

Export and re-import full simulation plan structs as JSON:

```elixir
:ok =
  FirehoseSimulator.export_simulation_plan_to_json(
    simulation_plan,
    "/tmp/simulation-plan.json"
  )

{:ok, imported_plan} =
  FirehoseSimulator.import_simulation_plan_from_json("/tmp/simulation-plan.json")
```

Play the plan:

```elixir
{:ok, player_id, _result} = FirehoseSimulator.play(imported_plan)
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

Shift an in-memory simulation plan by a millisecond offset:

```elixir
{:ok, simulation_plan} =
  FirehoseSimulator.generate_simulation_plan_from_json(
    simulation_plan_params: "priv/simulation/simulation_plan_params.json"
  )

shifted_simulation_plan = FirehoseSimulator.shift_simulation_plan(simulation_plan, 5_000)
{:ok, _player_id, _result} = FirehoseSimulator.play(shifted_simulation_plan)
```
