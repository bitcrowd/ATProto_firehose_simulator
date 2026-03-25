import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :firehose_simulator, FirehoseSimulatorWeb.Endpoint,
  http: [ip: {0, 0, 0, 0, 0, 0, 0, 1}, port: 4002],
  secret_key_base: "/etS1HWMCDq9z3SVaT55c9QEr6YymSFLUsZM4/oTXBVLXJ9NL85YFW9BMX8c6tL6",
  server: false

config :firehose_simulator, PLCWeb.Endpoint,
  http: [ip: {0, 0, 0, 0, 0, 0, 0, 1}, port: 4003],
  secret_key_base: "kfQt3Rm2C6x1tYc6VornNqEFnIq+TKVqwCRUT11iS3edJXg7dDWFUV8sozPq/Hva",
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
