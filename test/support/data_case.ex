defmodule FirehoseSimulator.DataCase do
  @moduledoc """
  Shared database test setup that manages the SQL sandbox owner lifecycle.
  """

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import FirehoseSimulator.DataCase
      alias FirehoseSimulator.Repo
    end
  end

  setup tags do
    FirehoseSimulator.DataCase.setup_sandbox(tags)
    :ok
  end

  def setup_sandbox(tags) do
    pid = Sandbox.start_owner!(FirehoseSimulator.Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)
  end
end
