defmodule FirehoseSimulatorWeb.CleanupLiveTest do
  use FirehoseSimulatorWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders the cleanup page and navigation", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/cleanup")

    assert has_element?(view, "#global-page-nav")
    assert has_element?(view, "#nav-firehose-control")
    assert has_element?(view, "#cleanup-form")
    assert has_element?(view, "#cleanup-notice")
    assert has_element?(view, "#preview-cleanup-button")
    refute has_element?(view, "#run-cleanup-button")
  end

  test "validates the database url", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/cleanup")

    html =
      view
      |> form("#cleanup-form", %{"cleanup" => %{"database_url" => "not-a-url"}})
      |> render_change()

    assert html =~ "Database URL must be postgres:// or postgresql://"
  end
end
