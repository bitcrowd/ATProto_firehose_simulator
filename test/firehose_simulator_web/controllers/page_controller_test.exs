defmodule FirehoseSimulatorWeb.PageControllerTest do
  use FirehoseSimulatorWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/setup"
  end
end
