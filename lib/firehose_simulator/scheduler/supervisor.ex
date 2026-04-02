defmodule FirehoseSimulator.Scheduler.Supervisor do
  @moduledoc """
  Supervisor for the scheduler worker pool.

  Started dynamically by `FirehoseSimulator.Player.play/2` and stopped by
  `FirehoseSimulator.Player.stop/0`.
  This is a separate supervisor so the entire scheduling infrastructure can be
  started/stopped as a unit without affecting the Store or Repo.
  """
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    scheduler_count = Keyword.get(opts, :scheduler_count, System.schedulers_online())
    worker_max_concurrency = Keyword.get(opts, :worker_max_concurrency)
    event_feeder_opts = Keyword.get(opts, :event_feeder_opts)

    workers =
      for partition <- 0..(scheduler_count - 1) do
        Supervisor.child_spec(
          {FirehoseSimulator.Scheduler.Worker,
           [
             partition: partition,
             num_partitions: scheduler_count,
             max_concurrency: worker_max_concurrency
           ]},
          id: {FirehoseSimulator.Scheduler.Worker, partition}
        )
      end

    event_feeder =
      if event_feeder_opts do
        [{FirehoseSimulator.SimulationPlan.EventFeeder, event_feeder_opts}]
      else
        []
      end

    children = workers ++ event_feeder

    Supervisor.init(children, strategy: :one_for_all)
  end
end
