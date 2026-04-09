defmodule FirehoseSimulator.Player.Scheduler.Supervisor do
  @moduledoc """
  Supervisor for the scheduler worker pool.

  Started dynamically by `FirehoseSimulator.Player.play/2` and stopped by
  `FirehoseSimulator.Player.stop/0`.
  This is a separate supervisor so the entire scheduling infrastructure can be
  started/stopped as a unit without affecting the Store or Repo.
  """
  use Supervisor

  def start_link(opts) do
    name = Keyword.get(opts, :name)

    if name do
      Supervisor.start_link(__MODULE__, opts, name: name)
    else
      Supervisor.start_link(__MODULE__, opts)
    end
  end

  @impl true
  def init(opts) do
    player_id = Keyword.fetch!(opts, :player_id)
    store_name = Keyword.fetch!(opts, :store_name)
    event_feeder_name = Keyword.fetch!(opts, :event_feeder_name)
    scheduler_count = Keyword.get(opts, :scheduler_count, System.schedulers_online())
    worker_max_concurrency = Keyword.get(opts, :worker_max_concurrency)
    event_feeder_opts = Keyword.get(opts, :event_feeder_opts)

    store = {FirehoseSimulator.Player.Store, [name: store_name]}

    workers =
      for partition <- 0..(scheduler_count - 1) do
        Supervisor.child_spec(
          {FirehoseSimulator.Player.Scheduler.Worker,
           [
             player_id: player_id,
             partition: partition,
             num_partitions: scheduler_count,
             store: store_name,
             max_concurrency: worker_max_concurrency
           ]},
          id: {FirehoseSimulator.Player.Scheduler.Worker, player_id, partition}
        )
      end

    event_feeder =
      if event_feeder_opts do
        [
          {FirehoseSimulator.Player.EventFeeder,
           event_feeder_opts
           |> Keyword.put(:name, event_feeder_name)
           |> Keyword.put(:store, store_name)}
        ]
      else
        []
      end

    children = [store] ++ workers ++ event_feeder

    Supervisor.init(children, strategy: :one_for_all)
  end
end
