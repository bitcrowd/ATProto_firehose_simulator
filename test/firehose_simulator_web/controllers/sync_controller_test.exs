defmodule FirehoseSimulatorWeb.SyncControllerTest do
  use FirehoseSimulatorWeb.ConnCase

  test "GET /xrpc/com.atproto.sync.listRepos", %{conn: conn} do
    conn = get(conn, ~p"/xrpc/com.atproto.sync.listRepos")

    assert json_response(conn, 200) == %{"repos" => []}
  end
end
