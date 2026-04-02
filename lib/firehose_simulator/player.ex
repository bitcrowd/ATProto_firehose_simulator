defmodule FirehoseSimulator.Player do
  @moduledoc """
  Process orchestration API for simulation-plan runs.

  A run starts immediately when you pass an in-memory
  `%FirehoseSimulator.SimulationPlan{}` to `play/2`.
  """

  alias FirehoseSimulator.Scheduler
  alias FirehoseSimulator.SimulationPlan
  alias FirehoseSimulator.SimulationPlan.EventFeeder
  alias FirehoseSimulator.Store

  @spec play(SimulationPlan.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def play(%SimulationPlan{} = simulation_plan, opts \\ []) do
    time_offset_ms = Keyword.get(opts, :time_offset_ms, 0)
    request_interval_ms = Keyword.get(opts, :request_interval_ms, 30_000)
    scheduler_count = Keyword.get(opts, :scheduler_count, System.schedulers_online())
    worker_max_concurrency = Keyword.get(opts, :worker_max_concurrency)

    with :ok <- ensure_store_started(),
         :ok <- ensure_not_running() do
      Store.clear()
      Store.ensure_partition_tables(scheduler_count)

      event_feeder_opts = [
        simulation_plan: simulation_plan,
        time_offset_ms: time_offset_ms,
        request_interval_ms: request_interval_ms,
        scheduler_count: scheduler_count
      ]

      scheduler_opts = [
        scheduler_count: scheduler_count,
        event_feeder_opts: event_feeder_opts
      ]

      scheduler_opts =
        if is_integer(worker_max_concurrency) and worker_max_concurrency > 0 do
          Keyword.put(scheduler_opts, :worker_max_concurrency, worker_max_concurrency)
        else
          scheduler_opts
        end

      case Scheduler.Supervisor.start_link(scheduler_opts) do
        {:ok, pid} ->
          Process.unlink(pid)
          :ok = EventFeeder.start_feeding()

          {:ok,
           %{
             request_interval_ms: request_interval_ms,
             schedulers: scheduler_count,
             supervisor: pid,
             started?: true
           }}

        error ->
          error
      end
    end
  end

  @doc "Clear ETS-backed simulation state."
  def reset do
    with :ok <- ensure_store_started() do
      Store.clear()
    end
  end

  @doc "Stop the running scheduler + feeder process tree."
  def stop do
    case Process.whereis(Scheduler.Supervisor) do
      nil ->
        {:error, :not_running}

      pid ->
        Supervisor.stop(pid, :normal)
        :ok
    end
  end

  @doc "Return coarse process and queue status."
  def status do
    loaded? = Process.whereis(EventFeeder) != nil
    running? = Process.whereis(Scheduler.Supervisor) != nil
    feeder_status = if loaded?, do: EventFeeder.status(), else: %{started?: false}

    %{
      running?: running?,
      loaded?: loaded?,
      active_sessions: safe_store_count(:active),
      completed_sessions: safe_store_count(:completed),
      feeder: feeder_status
    }
  end

  defp ensure_store_started do
    case Process.whereis(Store) do
      nil ->
        case Store.start_link([]) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          error -> error
        end

      _pid ->
        :ok
    end
  end

  defp ensure_not_running do
    case Process.whereis(Scheduler.Supervisor) do
      nil -> :ok
      _pid -> {:error, :already_running}
    end
  end

  defp safe_store_count(kind) do
    case Process.whereis(Store) do
      nil ->
        0

      _pid ->
        case kind do
          :active -> Store.count_active()
          :completed -> Store.count_completed()
        end
    end
  end
end
