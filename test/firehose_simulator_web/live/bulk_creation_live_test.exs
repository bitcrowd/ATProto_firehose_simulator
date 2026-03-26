defmodule FirehoseSimulatorWeb.BulkCreationLiveTest do
  use FirehoseSimulatorWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias FirehoseSimulator.BulkCreation

  setup do
    :ok = BulkCreation.reset()
    on_exit(fn -> BulkCreation.reset() end)
    :ok
  end

  test "renders the bulk creation page", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/bulk-creation")

    assert has_element?(view, "#bulk-connection-form")
    assert has_element?(view, "#bulk-follows-form")
    assert has_element?(view, "#bulk-posts-form")
    assert has_element?(view, "#tab-nav a[href=\"/bulk-creation\"][aria-current=\"page\"]")
    assert has_element?(view, "#bulk-last-user-id")
    assert has_element?(view, "#bulk-last-post-sequence")
    refute has_element?(view, "#follows-csv-upload")
    refute has_element?(view, "#posts-csv-upload")
  end

  test "shows validation errors for an invalid connection string", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/bulk-creation")

    html =
      view
      |> form("#bulk-connection-form", %{"connection" => %{"connection_string" => "not-a-url"}})
      |> render_submit()

    assert html =~ "Connection string must be a postgres URL"
  end

  test "requires a positive follow count", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/bulk-creation")

    html =
      view
      |> form("#bulk-follows-form", %{"follows_job" => %{"count" => "0"}})
      |> render_submit()

    assert html =~ "Count must be greater than 0"
  end

  test "shows an error when posts are submitted without a connection", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/bulk-creation")

    view
    |> form("#bulk-posts-form", %{"posts_job" => %{"count" => "2"}})
    |> render_submit()

    assert render(view) =~ "Set a database connection string first"
  end
end
