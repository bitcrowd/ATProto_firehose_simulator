import Config
import Dotenvy

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
env_dir = System.get_env("RELEASE_ROOT") || File.cwd!()

source!([
  Path.absname(".env", env_dir),
  System.get_env()
])

# Start the endpoints when PHX_SERVER is set (releases need this).
if env!("PHX_SERVER", :boolean, false) do
  config :firehose_simulator, FirehoseSimulatorWeb.Endpoint, server: true
  config :firehose_simulator, PLCWeb.Endpoint, server: true
  config :firehose_simulator, PDSWeb.Endpoint, server: true
end

config :firehose_simulator,
  prometheus_exporter_port: env!("PROMETHEUS_PORT", :integer, 9568),
  finch_pool_size: env!("FINCH_POOL_SIZE", :integer, 200),
  default_userbase_json_path: env!("USERBASE_JSON", :string, "example/userbase.json")

config :firehose_simulator,
       :dataplane_url,
       env!("DATAPLANE_URL", :string, "http://localhost:2585")

config :firehose_simulator, :plc,
  multikey: env!("PLC_MULTIKEY", :string, "zQ3shaSUSFjTPxogQR7eQ9QGwKWUdMmrHyjNiUg9oGJ8Lefiv"),
  private_hex:
    env!(
      "PLC_PRIVATE_HEX",
      :string,
      "bfe084f28e8bd6a64cbc18eea04c17457c9c48ce34498bc635b19ec7530d5e4a"
    )

# Set PHX_IP=0.0.0.0 (e.g. in containers) to bind beyond loopback.
listen_ip =
  case env!("PHX_IP", :string, "127.0.0.1") |> String.to_charlist() |> :inet.parse_address() do
    {:ok, ip} -> ip
    {:error, _} -> {127, 0, 0, 1}
  end

config :firehose_simulator, FirehoseSimulatorWeb.Endpoint,
  http: [ip: listen_ip, port: env!("PORT", :integer, 4000)]

config :firehose_simulator, PLCWeb.Endpoint,
  http: [ip: listen_ip, port: env!("PLC_PORT", :integer, 4001)]

config :firehose_simulator, PDSWeb.Endpoint,
  http: [ip: listen_ip, port: env!("PDS_PORT", :integer, 4002)]

# Test manages its own Repo (sandbox); only configure dev/prod here.
if config_env() != :test do
  config :firehose_simulator, FirehoseSimulator.Repo,
    url: env!("DATABASE_URL", :string, "postgres://postgres:postgres@localhost:5432/dataplane"),
    pool_size: env!("POOL_SIZE", :integer, 10)
end

if config_env() == :prod do
  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    env!(
      "SECRET_KEY_BASE",
      :string,
      "z7rsbJmkyvb78au+8QVQnHMKFKLnFF5CoOGOfW4iLnNK/2XCe9D7NEqCN/kNqFf7"
    )

  plc_secret_key_base =
    env!(
      "PLC_SECRET_KEY_BASE",
      :string,
      "apBV7RYO0SMIcxQkDck4y/0cOxKX/WxaYO7uIu8OUpqgia/ti83YMX8q+N8F616i"
    )

  pds_secret_key_base =
    env!(
      "PDS_SECRET_KEY_BASE",
      :string,
      "N4yhNYi3cwI7AbQeoMs6c4jLlBNX13Kj4j1y+qjnCkA8jAJbcn5xjEhud9PF8rT2"
    )

  host = env!("PHX_HOST", :string, "localhost")

  config :firehose_simulator, :dns_cluster_query, env!("DNS_CLUSTER_QUERY", :string, nil)

  config :firehose_simulator, FirehoseSimulatorWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    secret_key_base: secret_key_base

  config :firehose_simulator, PLCWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    secret_key_base: plc_secret_key_base

  config :firehose_simulator, PDSWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    secret_key_base: pds_secret_key_base
end
