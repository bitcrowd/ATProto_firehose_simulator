defmodule FirehoseSimulator do
  @moduledoc """
  The top-level API for the firehose simulator.
  """

  require Logger

  alias FirehoseSimulator.BulkCreation
  alias FirehoseSimulator.BulkCreation.Vacuum
  alias FirehoseSimulator.DatabaseConnection
  alias FirehoseSimulator.Player
  alias FirehoseSimulator.State
  alias FirehoseSimulator.SimulationPlan
  alias FirehoseSimulator.BaseData.Userbase

  @default_userbase_filename "priv/simulation/userbase.json"
  # Bulk Creation
  @spec create_userbase() :: {:ok, map()} | {:error, String.t()}
  def create_userbase do
    create_userbase(userbase_filename(), database_connection())
  end

  @spec create_userbase(String.t(), DatabaseConnection.t()) :: {:ok, map()} | {:error, String.t()}
  def create_userbase(path, %DatabaseConnection{} = connection) when is_binary(path) do
    with {:ok, userbase} <- load_userbase(path),
         {:ok, result} <- do_create_userbase(userbase, connection) do
      {:ok, result}
    end
  end

  @spec create_userbase(String.t(), String.t()) :: {:ok, map()} | {:error, String.t()}
  def create_userbase(path, connection_string)
      when is_binary(path) and is_binary(connection_string) do
    create_userbase(path, %DatabaseConnection{connection_string: connection_string})
  end

  @spec create_userbase(String.t()) :: {:ok, map()} | {:error, String.t()}
  def create_userbase(path) when is_binary(path) do
    create_userbase(path, database_connection())
  end

  @spec bulk_create_simulation_plan(SimulationPlan.t()) :: {:ok, map()} | {:error, String.t()}
  def bulk_create_simulation_plan(%SimulationPlan{} = simulation_plan) do
    bulk_create_simulation_plan(simulation_plan, database_connection())
  end

  @spec bulk_create_simulation_plan(SimulationPlan.t(), DatabaseConnection.t()) ::
          {:ok, map()} | {:error, String.t()}
  def bulk_create_simulation_plan(
        %SimulationPlan{} = simulation_plan,
        %DatabaseConnection{} = connection
      ) do
    Logger.info("creating simulation plan data in database")

    case BulkCreation.create_simulation_plan(simulation_plan, connection) do
      {:ok, result} = ok ->
        Logger.info("created simulation plan data: #{inspect(result)}")
        ok

      {:error, reason} = error ->
        Logger.error("failed to create simulation plan data: #{reason}")
        error
    end
  end

  @spec vacuum() :: {:ok, map()} | {:error, String.t()}
  def vacuum do
    vacuum([])
  end

  @spec vacuum(keyword()) :: {:ok, map()} | {:error, String.t()}
  def vacuum(opts) when is_list(opts) do
    vacuum(database_connection().connection_string, opts)
  end

  @spec vacuum(String.t(), keyword()) :: {:ok, map()} | {:error, String.t()}
  def vacuum(connection_string, opts)
      when is_binary(connection_string) and is_list(opts) do
    Logger.info("running vacuum actions")

    case Vacuum.run(connection_string, opts) do
      {:ok, result} = ok ->
        Logger.info("completed vacuum actions: #{inspect(result)}")
        ok

      {:error, reason} = error ->
        Logger.error("failed vacuum actions: #{inspect(reason)}")
        error
    end
  end

  defp userbase_filename do
    System.get_env("USERBASE_JSON", @default_userbase_filename)
  end

  defp database_connection do
    case state_connection_string() do
      nil -> DatabaseConnection.default()
      connection_string -> %DatabaseConnection{connection_string: connection_string}
    end
  end

  defp state_connection_string do
    try do
      State.get_db_connection_string()
    catch
      :exit, _reason -> nil
    end
  end

  defp load_userbase(path) do
    Logger.info("loading userbase from #{path}")

    case(Userbase.load_file(path)) do
      {:ok, userbase} ->
        Logger.info(
          "loaded userbase #{userbase.name} from #{path} with #{userbase.num_users} users"
        )

        {:ok, userbase}

      {:error, reason} ->
        Logger.error("failed to load userbase from #{path}: #{reason}")
        {:error, reason}
    end
  end

  defp do_create_userbase(userbase, connection) do
    Logger.info("creating userbase #{userbase.name} in database for #{userbase.num_users} users")

    case BulkCreation.create_userbase(userbase, connection) do
      {:ok, result} ->
        Logger.info("created userbase \"#{userbase.name}\": #{inspect(result)}")
        {:ok, result}

      {:error, reason} ->
        Logger.error("failed to create userbase #{userbase.name}: #{reason}")
        {:error, reason}
    end
  end

  # Simulation Plan

  @spec generate_simulation_plan_from_json(String.t()) ::
          {:ok, SimulationPlan.t()} | {:error, String.t()}
  def generate_simulation_plan_from_json(path) when is_binary(path) do
    generate_simulation_plan_from_json(simulation_plan_params: path)
  end

  @spec generate_simulation_plan_from_json(keyword(String.t())) ::
          {:ok, SimulationPlan.t()} | {:error, String.t()}
  def generate_simulation_plan_from_json(opts) do
    Logger.info("generating simulation plan from params json file: #{inspect(opts)}")

    case SimulationPlan.generate_from_json(opts) do
      {:ok, plan} ->
        Logger.info("generated simulation plan sections")
        {:ok, plan}

      {:error, reason} ->
        Logger.error("failed to generate simulation plan from json: #{reason}")
        {:error, reason}
    end
  end

  @spec import_simulation_plan_from_json(String.t()) ::
          {:ok, SimulationPlan.t()} | {:error, String.t()}
  def import_simulation_plan_from_json(path) when is_binary(path) do
    Logger.info("importing simulation plan from json file: #{path}")
    SimulationPlan.from_json_file(path)
  end

  @spec export_simulation_plan_to_json(SimulationPlan.t(), String.t()) ::
          :ok | {:error, String.t()}
  def export_simulation_plan_to_json(%SimulationPlan{} = simulation_plan, path)
      when is_binary(path) do
    with {:ok, json} <- SimulationPlan.to_json(simulation_plan),
         :ok <- File.write(path, json) do
      :ok
    else
      {:error, reason} when is_binary(reason) -> {:error, reason}
      {:error, reason} -> {:error, "failed to write simulation plan json: #{inspect(reason)}"}
    end
  end

  @spec shift_simulation_plan(SimulationPlan.t(), integer()) :: SimulationPlan.t()
  def shift_simulation_plan(%SimulationPlan{} = simulation_plan, offset_ms)
      when is_integer(offset_ms) do
    SimulationPlan.shift(simulation_plan, offset_ms)
  end

  # Player

  @spec play(SimulationPlan.t(), keyword()) :: {:ok, String.t(), map()} | {:error, term()}
  def play(%SimulationPlan{} = simulation_plan, opts \\ []) do
    Logger.info("starting simulation playback")

    case Player.play(simulation_plan, opts) do
      {:ok, _player_id, _result} = ok ->
        Logger.info("simulation playback started")
        ok

      {:error, reason} = error ->
        Logger.error("failed to start simulation playback: #{inspect(reason)}")
        error
    end
  end

  @spec play_with_offset(SimulationPlan.t(), integer()) ::
          {:ok, String.t(), map()} | {:error, term()}
  def play_with_offset(%SimulationPlan{} = simulation_plan, offset_ms)
      when is_integer(offset_ms) do
    play_with_offset(simulation_plan, offset_ms, [])
  end

  @spec play_with_offset(SimulationPlan.t(), integer(), keyword()) ::
          {:ok, String.t(), map()} | {:error, term()}
  def play_with_offset(%SimulationPlan{} = simulation_plan, offset_ms, opts)
      when is_integer(offset_ms) and is_list(opts) do
    simulation_plan
    |> shift_simulation_plan(offset_ms)
    |> play(opts)
  end

  @spec stop(String.t()) :: :ok | {:error, term()}
  def stop(player_id) when is_binary(player_id) do
    Logger.info("stopping simulation playback")

    case Player.stop(player_id) do
      :ok = ok ->
        Logger.info("simulation playback stopped for #{player_id}")
        ok

      {:error, reason} = error ->
        Logger.error("failed to stop simulation playback for #{player_id}: #{inspect(reason)}")
        error
    end
  end

  @spec stop() :: :ok
  def stop do
    Logger.info("stopping all simulation playback")
    :ok = Player.stop_all()
    Logger.info("all simulation playback stopped")
    :ok
  end

  @spec reset(String.t()) :: :ok | {:error, term()}
  def reset(player_id) when is_binary(player_id) do
    Logger.info("resetting simulation playback")

    case Player.reset(player_id) do
      :ok = ok ->
        Logger.info("simulation playback reset for #{player_id}")
        ok

      {:error, reason} = error ->
        Logger.error("failed to reset simulation playback for #{player_id}: #{inspect(reason)}")
        error
    end
  end

  @spec reset() :: :ok
  def reset do
    Logger.info("resetting all simulation playback")
    :ok = Player.reset_all()
    Logger.info("all simulation playback reset")
    :ok
  end

  @spec stop_all() :: :ok
  def stop_all, do: stop()

  @spec reset_all() :: :ok
  def reset_all, do: reset()

  @spec status(String.t()) :: map() | {:error, term()}
  def status(player_id) when is_binary(player_id), do: Player.status(player_id)
end
