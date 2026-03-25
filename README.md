# FirehoseSimulator

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`


The firehose simulator will start on [`localhost:4000`](http://localhost:4000).

The PLC stub will start on [`localhost:4001`](http://localhost:4001).

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

```bash
git apply wintermute.patch
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

4. Set up pnpm

- needs version > 9 but is locked to > 8
```bash
git apply atproto_blacksky.patch
```

5. Follow [instructions](https://github.com/blacksky-algorithms/atproto/?tab=readme-ov-file#setup) to run dataplane and AppView

```bash
node services/bsky/dataplane.js
```

```bash
BSKY_SERVICE_SIGNING_KEY=bfe084f28e8bd6a64cbc18eea04c17457c9c48ce34498bc635b19ec7530d5e4a node services/bsky/api.js
```

6. Clone rsky to run wintermute

```bash
git clone https://github.com/blacksky-algorithms/rsky/

git apply wintermute.patch
```

7. Set environment
```bash
export RELAY_HOSTS="http://localhost:4001" # to firehose simulator 
export DATABASE_URL="postgres://postgres:postgres@localhost:5432/atproto_blacksky?options=-csearch_path%3Dbsky" # according to step 2 
```

8. We must fix the DB schema to expected format

```bash
psql $DATABASE_URL -c "CREATE TABLE IF NOT EXISTS bsky.sub_state (service varchar NOT NULL PRIMARY KEY, cursor bigint NOT NULL);"
psql $DATABASE_URL -c "ALTER TABLE bsky.record ADD COLUMN IF NOT EXISTS rev text;"
```

9. Follow [instructions for running wintermute](https://github.com/blacksky-algorithms/rsky/blob/main/rsky-wintermute/README.md)


```bash
cargo build --release --package rsky-wintermute

./target/release/wintermute
```

## Create an account

`elixir pds_create_account.exs`

## Get the timeline

`elixir pds_timeline.exs`
