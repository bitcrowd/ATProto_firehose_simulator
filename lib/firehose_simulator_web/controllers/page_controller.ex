defmodule FirehoseSimulatorWeb.PageController do
  use FirehoseSimulatorWeb, :controller

  def home(conn, _params) do
    redirect(conn, to: ~p"/firehose")
  end
end
