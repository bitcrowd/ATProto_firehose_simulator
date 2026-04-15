defmodule FirehoseSimulator.DataCase do
  @moduledoc """
  This module defines the test case to be used by tests
  that interact with the data layer.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias FirehoseSimulator.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import FirehoseSimulator.DataCase
    end
  end

  setup tags do
    FirehoseSimulator.DataCase.setup_sandbox(tags)
    :ok
  end

  def setup_sandbox(tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(FirehoseSimulator.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
  end
end
