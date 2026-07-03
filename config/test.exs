import Config

config :firehose_simulator, :plc,
  multikey: System.get_env("PLC_MULTIKEY", "zQ3shaSUSFjTPxogQR7eQ9QGwKWUdMmrHyjNiUg9oGJ8Lefiv"),
  private_hex:
    System.get_env(
      "PLC_PRIVATE_HEX",
      "bfe084f28e8bd6a64cbc18eea04c17457c9c48ce34498bc635b19ec7530d5e4a"
    )

config :firehose_simulator,
       :dataplane_url,
       System.get_env("DATAPLANE_URL", "http://localhost:2585")

config :firehose_simulator, :run_storage_enabled, false
config :firehose_simulator, :start_player_infrastructure, false

config :firehose_simulator, FirehoseSimulator.Repo,
  url: "postgres://postgres:postgres@localhost:5432/dataplane_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :firehose_simulator, FirehoseSimulatorWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "/etS1HWMCDq9z3SVaT55c9QEr6YymSFLUsZM4/oTXBVLXJ9NL85YFW9BMX8c6tL6",
  server: false

config :firehose_simulator, PLCWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4003],
  secret_key_base: "kfQt3Rm2C6x1tYc6VornNqEFnIq+TKVqwCRUT11iS3edJXg7dDWFUV8sozPq/Hva",
  server: false

config :firehose_simulator, PDSWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4004],
  secret_key_base: "rqHMXWf8gZY5nKjrtxG7p3wL9HF+V3Tf+nJZ8Q0TWKkf1rB5RMo7aLduBzY4xckX",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
