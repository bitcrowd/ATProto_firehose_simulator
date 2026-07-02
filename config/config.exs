# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :firehose_simulator,
  ecto_repos: [FirehoseSimulator.Repo],
  generators: [timestamp_type: :utc_datetime],
  default_userbase_json_path: "example/userbase.json",
  log_file_path: "log/firehose_simulator.log",
  run_storage_enabled: true,
  prometheus_exporter_port: 9568

# Configure the endpoint
config :firehose_simulator, FirehoseSimulatorWeb.Endpoint,
  url: [host: "127.0.0.1"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: FirehoseSimulatorWeb.ErrorHTML, json: FirehoseSimulatorWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: FirehoseSimulator.PubSub,
  live_view: [signing_salt: "i6CxHF/S"]

# Configure the endpoint
config :firehose_simulator, PLCWeb.Endpoint,
  url: [host: "127.0.0.1"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: FirehoseSimulatorWeb.ErrorHTML, json: FirehoseSimulatorWeb.ErrorJSON],
    layout: false
  ],
  live_view: [signing_salt: "i6CxHF/S"]

config :firehose_simulator, PDSWeb.Endpoint,
  url: [host: "127.0.0.1"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: FirehoseSimulatorWeb.ErrorHTML, json: FirehoseSimulatorWeb.ErrorJSON],
    layout: false
  ],
  live_view: [signing_salt: "i6CxHF/S"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  firehose_simulator: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  firehose_simulator: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
