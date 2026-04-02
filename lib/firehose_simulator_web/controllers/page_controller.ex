defmodule FirehoseSimulatorWeb.PageController do
  use FirehoseSimulatorWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
