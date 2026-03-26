defmodule FirehoseSimulatorWeb.FirehoseControlLiveTest do
  use FirehoseSimulatorWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias FirehoseSimulator.Firehose

  setup do
    :ok = Firehose.reset()
    on_exit(fn -> Firehose.reset() end)
    :ok
  end

  test "renders the empty event state", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#event-config-form")
    assert has_element?(view, "#configured-events-empty")
    refute has_element?(view, "#configured-events")
    refute render(view) =~ "Current DID"
  end

  test "shows follow inputs for manual graph follow", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    html =
      view
      |> form("#event-config-form", %{
        "event_config" => %{"type" => "app.bsky.graph.follow", "random" => "false"}
      })
      |> render_change()

    assert html =~ "event_config_author_did"
    assert html =~ "event_config_subject_did"
    refute html =~ "event_config_text"
  end

  test "shows post inputs for manual post create", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    html =
      view
      |> form("#event-config-form", %{
        "event_config" => %{"type" => "app.bsky.feed.post", "random" => "false"}
      })
      |> render_change()

    assert html =~ "event_config_author_did"
    assert html =~ "event_config_text"
    refute html =~ "event_config_subject_did"
  end

  test "adds a manual follow row", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> form("#event-config-form", %{
      "event_config" => %{"type" => "app.bsky.graph.follow", "random" => "false"}
    })
    |> render_change()

    view
    |> form("#event-config-form", %{
      "event_config" => %{
        "type" => "app.bsky.graph.follow",
        "random" => "false",
        "author_did" => "did:plc:author123",
        "subject_did" => "did:plc:subject123"
      }
    })
    |> render_submit()

    assert has_element?(view, "#configured-events")
    html = render(view)
    assert html =~ "app.bsky.graph.follow"
    assert html =~ "did:plc:author123"
    assert html =~ "did:plc:subject123"
    assert row_html(html, "app.bsky.graph.follow") =~ ~r/>\s*0\s*</
  end

  test "adds a manual post row", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> form("#event-config-form", %{
      "event_config" => %{"type" => "app.bsky.feed.post", "random" => "false"}
    })
    |> render_change()

    view
    |> form("#event-config-form", %{
      "event_config" => %{
        "type" => "app.bsky.feed.post",
        "random" => "false",
        "author_did" => "did:plc:author123",
        "text" => "hello from liveview"
      }
    })
    |> render_submit()

    html = render(view)
    assert html =~ "app.bsky.feed.post"
    assert html =~ "hello from liveview"
    assert row_html(html, "app.bsky.feed.post") =~ ~r/>\s*0\s*</
  end

  test "adds a random row", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> form("#event-config-form", %{
      "event_config" => %{"type" => "app.bsky.feed.post", "random" => "true"}
    })
    |> render_submit()

    html = render(view)
    assert html =~ "Random"
    assert html =~ "Post content generated at emit time"
    assert row_html(html, "app.bsky.feed.post") =~ ~r/>\s*0\s*</
  end

  test "updates emitted count after a firehose tick", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> form("#event-config-form", %{
      "event_config" => %{"type" => "app.bsky.graph.follow", "random" => "false"}
    })
    |> render_change()

    view
    |> form("#event-config-form", %{
      "event_config" => %{
        "type" => "app.bsky.graph.follow",
        "random" => "false",
        "author_did" => "did:plc:author123",
        "subject_did" => "did:plc:subject123"
      }
    })
    |> render_submit()

    send(Firehose, :event)
    _state = :sys.get_state(Firehose)
    send(view.pid, :refresh_status)

    assert row_html(render(view), "app.bsky.graph.follow") =~ ~r/>\s*1\s*</
  end

  test "shows validation errors for an invalid manual follow", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> form("#event-config-form", %{
      "event_config" => %{"type" => "app.bsky.graph.follow", "random" => "false"}
    })
    |> render_change()

    html =
      view
      |> form("#event-config-form", %{
        "event_config" => %{
          "type" => "app.bsky.graph.follow",
          "random" => "false",
          "author_did" => "did:plc:author123",
          "subject_did" => ""
        }
      })
      |> render_submit()

    assert html =~ "Subject DID is required"
    assert has_element?(view, "#configured-events-empty")
  end

  test "shows validation errors for an invalid manual post", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> form("#event-config-form", %{
      "event_config" => %{"type" => "app.bsky.feed.post", "random" => "false"}
    })
    |> render_change()

    html =
      view
      |> form("#event-config-form", %{
        "event_config" => %{
          "type" => "app.bsky.feed.post",
          "random" => "false",
          "author_did" => "did:plc:author123",
          "text" => ""
        }
      })
      |> render_submit()

    assert html =~ "Text is required"
    assert has_element?(view, "#configured-events-empty")
  end

  defp row_html(html, type) do
    ~r/<tr id="configured-event-\d+".*?<\/tr>/s
    |> Regex.scan(html)
    |> Enum.map(&List.first/1)
    |> Enum.find(&String.contains?(&1, type))
    |> case do
      nil -> raise "row for #{type} not found"
      row -> row
    end
  end
end
