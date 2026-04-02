defmodule FirehoseSimulator do
  @moduledoc """
  FirehoseSimulator keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  require Logger

  alias FirehoseSimulator.BulkCreation
  alias FirehoseSimulator.DatabaseConnection
  alias FirehoseSimulator.Player
  alias FirehoseSimulator.State
  alias FirehoseSimulator.SimulationPlan
  alias FirehoseSimulator.SimulationPlan.Userbase

  @default_userbase_filename "priv/simulation/userbase.json"
  @default_connection_string "postgres://postgres:postgres@localhost:5432/atproto_blacksky?options=-csearch_path%3Dbsky"

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

  @spec load_simulation_plan_from_json(String.t()) ::
          {:ok, SimulationPlan.t()} | {:error, String.t()}
  def load_simulation_plan_from_json(path) when is_binary(path) do
    load_simulation_plan_from_json(simulation_plan_params: path)
  end

  @spec load_simulation_plan_from_json(keyword(String.t())) ::
          {:ok, SimulationPlan.t()} | {:error, String.t()}
  def load_simulation_plan_from_json(opts) do
    Logger.info("loading simulation plan from json file: #{inspect(opts)}")

    case SimulationPlan.load_from_json(opts) do
      {:ok, plan} ->
        Logger.info("loaded simulation plan sections")
        {:ok, plan}

      {:error, reason} ->
        Logger.error("failed to load simulation plan from json: #{reason}")
        {:error, reason}
    end
  end

  @spec play(SimulationPlan.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def play(%SimulationPlan{} = simulation_plan, opts \\ []) do
    Logger.info("starting simulation playback")

    case Player.play(simulation_plan, opts) do
      {:ok, _result} = ok ->
        Logger.info("simulation playback started")
        ok

      {:error, reason} = error ->
        Logger.error("failed to start simulation playback: #{inspect(reason)}")
        error
    end
  end

  def stop, do: Player.stop()

  def reset, do: Player.reset()

  @spec shift_simulation_plan(SimulationPlan.t(), integer()) :: SimulationPlan.t()
  def shift_simulation_plan(%SimulationPlan{} = simulation_plan, offset_ms)
      when is_integer(offset_ms) do
    %SimulationPlan{
      posts: shift_events(simulation_plan.posts, offset_ms),
      sessions: shift_events(simulation_plan.sessions, offset_ms),
      follows: shift_events(simulation_plan.follows, offset_ms)
    }
  end

  defp userbase_filename do
    System.get_env("USERBASE_JSON", @default_userbase_filename)
  end

  defp database_connection do
    %DatabaseConnection{
      connection_string:
        state_connection_string() || System.get_env("DATABASE_URL") || @default_connection_string
    }
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

  defp shift_events(nil, _offset_ms), do: nil

  defp shift_events(events, offset_ms) when is_list(events) do
    Enum.map(events, fn event ->
      Map.update!(event, :offset_ms, &(&1 + offset_ms))
    end)
  end
end
