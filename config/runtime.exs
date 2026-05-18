import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/firehose_simulator start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :firehose_simulator, FirehoseSimulatorWeb.Endpoint, server: true
  config :firehose_simulator, PLCWeb.Endpoint, server: true
  config :firehose_simulator, PDSWeb.Endpoint, server: true
end

config :firehose_simulator,
  prometheus_exporter_port: String.to_integer(System.get_env("PROMETHEUS_PORT", "9568")),
  finch_pool_size: String.to_integer(System.get_env("FINCH_POOL_SIZE", "200"))

config :firehose_simulator, FirehoseSimulatorWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

config :firehose_simulator, PLCWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PLC_PORT", "4001"))]

config :firehose_simulator, PDSWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PDS_PORT", "4002"))]

if config_env() == :prod do
  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      "z7rsbJmkyvb78au+8QVQnHMKFKLnFF5CoOGOfW4iLnNK/2XCe9D7NEqCN/kNqFf7"

  plc_secret_key_base =
    System.get_env("PLC_SECRET_KEY_BASE") ||
      "apBV7RYO0SMIcxQkDck4y/0cOxKX/WxaYO7uIu8OUpqgia/ti83YMX8q+N8F616i"

  pds_secret_key_base =
    System.get_env("PDS_SECRET_KEY_BASE") ||
      "N4yhNYi3cwI7AbQeoMs6c4jLlBNX13Kj4j1y+qjnCkA8jAJbcn5xjEhud9PF8rT2"

  host = System.get_env("PHX_HOST") || "localhost"

  config :firehose_simulator, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :firehose_simulator, FirehoseSimulatorWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {127, 0, 0, 1}],
    secret_key_base: secret_key_base

  config :firehose_simulator, PLCWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {127, 0, 0, 1}],
    secret_key_base: plc_secret_key_base

  config :firehose_simulator, PDSWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {127, 0, 0, 1}],
    secret_key_base: pds_secret_key_base
end
