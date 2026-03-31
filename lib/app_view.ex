defmodule AppView do
  alias AppView.Auth

  def new(options \\ []) when is_list(options) do
    Req.new(base_url: app_view_url())
    |> Req.Request.append_request_steps(
      post: fn req ->
        with %{method: :get, body: <<_::binary>>} <- req do
          %{req | method: :post}
        end
      end
    )
    |> Req.merge(options)
  end

  def request(url, options \\ []), do: Req.request(new(url: url), options)

  def request!(url, options \\ []), do: Req.request!(new(url: url), options)

  def get_timeline(did, limit \\ 20) do
    method = "app.bsky.feed.getTimeline"
    token = bearer_token(did, method)

    with {:ok, response} <-
           request("/xrpc/#{method}",
             auth: {:bearer, token},
             params: [limit: limit]
           ) do
      response.body
    end
  end

  defp app_view_url do
    Application.fetch_env!(:firehose_simulator, :bsky_api_url)
  end

  defp app_view_did do
    Application.fetch_env!(:firehose_simulator, :bsky_did)
  end

  defp bearer_token(did, lexicon_method) do
    Auth.bearer_token(did, app_view_did(), lexicon_method)
  end
end
