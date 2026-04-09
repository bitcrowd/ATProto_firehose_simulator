defmodule Dataplane do
  def new(options \\ []) when is_list(options) do
    Req.new(base_url: dataplane_url())
    |> Req.merge(options)
  end

  def request(url, options \\ []), do: Req.request(new(url: url), options)

  def request!(url, options \\ []), do: Req.request!(new(url: url), options)

  def get_timeline(did, limit \\ 20, cursor \\ "") do
    with {:ok, response} <-
           request("/bsky.Service/GetTimeline",
             method: :post,
             json: %{actor_did: did, limit: limit, cursor: cursor}
           ) do
      response.body
    end
  end

  defp dataplane_url do
    Application.fetch_env!(:firehose_simulator, :dataplane_url)
  end
end
