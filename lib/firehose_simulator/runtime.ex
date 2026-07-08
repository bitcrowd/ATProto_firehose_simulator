defmodule FirehoseSimulator.Runtime do
  @moduledoc false

  use Supervisor

  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    run_storage_directory = Keyword.get(opts, :run_storage_directory)
    Supervisor.start_link(__MODULE__, run_storage_directory, name: name)
  end

  @impl true
  def init(run_storage_directory) do
    children = [
      {Registry, keys: :unique, name: FirehoseSimulator.Player.Registry},
      {Task.Supervisor, name: FirehoseSimulator.Player.TaskSupervisor},
      {DynamicSupervisor, name: FirehoseSimulator.PlayerSupervisor, strategy: :one_for_one},
      {FirehoseSimulator.State, run_storage_directory: run_storage_directory}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
