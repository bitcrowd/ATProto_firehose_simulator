defmodule FirehoseSimulator.TestTimelinePlug do
  @moduledoc false
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, opts) do
    agent = Keyword.fetch!(opts, :agent)

    case {conn.method, conn.request_path} do
      {"POST", "/bsky.Service/GetTimeline"} ->
        {_conn, response} =
          Agent.get_and_update(agent, fn
            [response | rest] -> {{conn, response}, rest}
            [] -> {{conn, {:ok, %{"items" => []}}}, []}
          end)

        send_timeline_response(conn, response)

      _other ->
        send_resp(conn, 404, "not found")
    end
  end

  defp send_timeline_response(conn, {:ok, body}) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(body))
  end

  defp send_timeline_response(conn, {:error, status, body}) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
