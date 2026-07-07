defmodule FirehoseSimulator.Metrics.PrometheusExporter do
  @moduledoc false

  import Plug.Conn

  def init(opts), do: opts

  def call(%Plug.Conn{method: "GET", request_path: "/metrics"} = conn, _opts) do
    body = TelemetryMetricsPrometheus.Core.scrape()
    conn |> put_resp_content_type("text/plain") |> send_resp(200, body)
  end

  def call(conn, _opts), do: send_resp(conn, 404, "not found")
end
