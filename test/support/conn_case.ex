defmodule FirehoseSimulatorWeb.ConnCase do
  @moduledoc """
  Shared connection test setup that wires route helpers and database sandboxing.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint FirehoseSimulatorWeb.Endpoint

      use FirehoseSimulatorWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import FirehoseSimulatorWeb.ConnCase
    end
  end

  setup tags do
    FirehoseSimulator.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
