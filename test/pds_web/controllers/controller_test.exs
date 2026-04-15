defmodule PDSWeb.ControllerTest do
  use FirehoseSimulatorWeb.ConnCase, async: true

  @endpoint PDSWeb.Endpoint

  test "returns 501 for unmatched routes", %{conn: conn} do
    conn = get(conn, "/xrpc/com.atproto.server.createSession")

    assert response(conn, 501) == "Not Implemented"
  end
end
