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

## Create an account

`elixir pds_create_account.exs`

## Get the timeline

`elixir pds_timeline.exs`
