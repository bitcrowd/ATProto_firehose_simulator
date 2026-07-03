defmodule PDSWeb.Controller do
  @moduledoc false
  use Phoenix.Controller, formats: [:json]

  require Logger

  def handle(conn, %{"path" => path}) do
    Logger.debug(fn ->
      "PDS request method=#{conn.method} path=/#{Enum.join(path, "/")} query=#{conn.query_string} headers=#{inspect(conn.req_headers)} params=#{inspect(conn.params)}"
    end)

    send_resp(conn, 501, "Not Implemented")
  end

  def handle(conn, _params) do
    Logger.debug(fn ->
      "PDS request method=#{conn.method} path=#{conn.request_path} query=#{conn.query_string} headers=#{inspect(conn.req_headers)} params=#{inspect(conn.params)}"
    end)

    send_resp(conn, 501, "Not Implemented")
  end
end
