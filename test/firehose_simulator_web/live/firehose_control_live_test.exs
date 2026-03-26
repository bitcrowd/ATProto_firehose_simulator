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
    {:ok, view, _html} = live(conn, ~p"/firehose")

    assert has_element?(view, "#event-config-form")
    assert has_element?(view, "#global-page-nav")
    assert has_element?(view, "#nav-cleanup")
    assert has_element?(view, "#event_config_time_ms")
    assert has_element?(view, "#configured-events-empty")
    assert has_element?(view, "#tab-nav a[href=\"/firehose\"][aria-current=\"page\"]")
    refute has_element?(view, "#configured-events")
    refute render(view) =~ "Current DID"
  end

  test "shows follow inputs for manual graph follow", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/firehose")

    html =
      view
      |> form("#event-config-form", %{
        "event_config" => %{
          "type" => "app.bsky.graph.follow",
          "random" => "false",
          "time_ms" => "1000"
        }
      })
      |> render_change()

    assert html =~ "event_config_author_did"
    assert html =~ "event_config_subject_did"
    refute html =~ "event_config_text"
  end

  test "shows post inputs for manual post create", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/firehose")

    html =
      view
      |> form("#event-config-form", %{
        "event_config" => %{
          "type" => "app.bsky.feed.post",
          "random" => "false",
          "time_ms" => "1000"
        }
      })
      |> render_change()

    assert html =~ "event_config_author_did"
    assert html =~ "event_config_text"
    refute html =~ "event_config_subject_did"
  end

  test "hides per-event inputs for random mode", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/firehose")

    html =
      view
      |> form("#event-config-form", %{
        "event_config" => %{
          "type" => "app.bsky.feed.post",
          "random" => "true",
          "time_ms" => "1000"
        }
      })
      |> render_change()

    refute html =~ "event_config_author_did"
    refute html =~ "event_config_text"
  end

  test "adds a manual follow row", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/firehose")

    view
    |> form("#event-config-form", %{
      "event_config" => %{
        "type" => "app.bsky.graph.follow",
        "random" => "false",
        "time_ms" => "1000"
      }
    })
    |> render_change()

    view
    |> form("#event-config-form", %{
      "event_config" => %{
        "type" => "app.bsky.graph.follow",
        "random" => "false",
        "time_ms" => "250",
        "author_did" => "did:sim:author123",
        "subject_did" => "did:sim:subject123"
      }
    })
    |> render_submit()

    assert has_element?(view, "#configured-events")
    html = render(view)
    assert html =~ "app.bsky.graph.follow"
    assert html =~ "did:sim:author123"
    assert html =~ "did:sim:subject123"
    assert html =~ "250 ms"
    assert card_html(html, "app.bsky.graph.follow") =~ ~r/>\s*0\s*</
  end

  test "adds a manual post row", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/firehose")

    view
    |> form("#event-config-form", %{
      "event_config" => %{
        "type" => "app.bsky.feed.post",
        "random" => "false",
        "time_ms" => "1000"
      }
    })
    |> render_change()

    view
    |> form("#event-config-form", %{
      "event_config" => %{
        "type" => "app.bsky.feed.post",
        "random" => "false",
        "time_ms" => "400",
        "author_did" => "did:sim:author123",
        "text" => "hello from liveview"
      }
    })
    |> render_submit()

    html = render(view)
    assert html =~ "app.bsky.feed.post"
    assert html =~ "hello from liveview"
    assert html =~ "400 ms"
    assert card_html(html, "app.bsky.feed.post") =~ ~r/>\s*0\s*</
  end

  test "adds a random row", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/firehose")

    view
    |> form("#event-config-form", %{
      "event_config" => %{"type" => "app.bsky.feed.post", "random" => "true", "time_ms" => "125"}
    })
    |> render_submit()

    html = render(view)
    assert html =~ "Random"
    assert html =~ "125 ms"
    assert html =~ "Post content generated at emit time"
    assert card_html(html, "app.bsky.feed.post") =~ ~r/>\s*0\s*</
  end

  test "updates emitted count after an event emission", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/firehose")

    view
    |> form("#event-config-form", %{
      "event_config" => %{
        "type" => "app.bsky.graph.follow",
        "random" => "false",
        "time_ms" => "1000"
      }
    })
    |> render_change()

    view
    |> form("#event-config-form", %{
      "event_config" => %{
        "type" => "app.bsky.graph.follow",
        "random" => "false",
        "time_ms" => "20",
        "author_did" => "did:sim:author123",
        "subject_did" => "did:sim:subject123"
      }
    })
    |> render_submit()

    assert_eventually(fn ->
      card_html(render(view), "app.bsky.graph.follow") =~ ~r/>\s*1\s*</
    end)
  end

  test "removes a configured event row", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/firehose")

    view
    |> form("#event-config-form", %{
      "event_config" => %{
        "type" => "app.bsky.feed.post",
        "random" => "true",
        "time_ms" => "1000"
      }
    })
    |> render_submit()

    [event] = Firehose.events()

    view
    |> element("#remove-event-#{event["id"]}")
    |> render_click()

    refute has_element?(view, "#configured-event-#{event["id"]}")
    assert has_element?(view, "#configured-events-empty")
    assert Firehose.events() == []
  end

  test "shows validation errors for an invalid manual follow", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/firehose")

    view
    |> form("#event-config-form", %{
      "event_config" => %{
        "type" => "app.bsky.graph.follow",
        "random" => "false",
        "time_ms" => "1000"
      }
    })
    |> render_change()

    html =
      view
      |> form("#event-config-form", %{
        "event_config" => %{
          "type" => "app.bsky.graph.follow",
          "random" => "false",
          "time_ms" => "1000",
          "author_did" => "did:sim:author123",
          "subject_did" => ""
        }
      })
      |> render_submit()

    assert html =~ "Subject DID is required"
    assert has_element?(view, "#configured-events-empty")
  end

  test "shows validation errors for an invalid manual post", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/firehose")

    view
    |> form("#event-config-form", %{
      "event_config" => %{
        "type" => "app.bsky.feed.post",
        "random" => "false",
        "time_ms" => "1000"
      }
    })
    |> render_change()

    html =
      view
      |> form("#event-config-form", %{
        "event_config" => %{
          "type" => "app.bsky.feed.post",
          "random" => "false",
          "time_ms" => "1000",
          "author_did" => "did:sim:author123",
          "text" => ""
        }
      })
      |> render_submit()

    assert html =~ "Text is required"
    assert has_element?(view, "#configured-events-empty")
  end

  test "shows validation errors for an invalid emit frequency", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/firehose")

    html =
      view
      |> form("#event-config-form", %{
        "event_config" => %{
          "type" => "app.bsky.feed.post",
          "random" => "true",
          "time_ms" => "0"
        }
      })
      |> render_submit()

    assert html =~ "Emit frequency must be greater than 0 ms"
    assert has_element?(view, "#configured-events-empty")
  end

  defp card_html(html, type) do
    ~r/<article id="configured-event-\d+".*?<\/article>/s
    |> Regex.scan(html)
    |> Enum.map(&List.first/1)
    |> Enum.find(&String.contains?(&1, type))
    |> case do
      nil -> raise "card for #{type} not found"
      card -> card
    end
  end

  defp assert_eventually(fun, attempts \\ 20)

  defp assert_eventually(fun, 1) do
    assert fun.()
  end

  defp assert_eventually(fun, attempts) do
    if fun.() do
      assert true
    else
      receive do
      after
        20 -> assert_eventually(fun, attempts - 1)
      end
    end
  end
end
