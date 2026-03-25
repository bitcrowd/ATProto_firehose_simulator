defmodule FirehoseSimulatorWeb.SyncController do
  use FirehoseSimulatorWeb, :controller

  def list_repos(conn, _params) do
    json(conn, %{repos: []})
  end
end
