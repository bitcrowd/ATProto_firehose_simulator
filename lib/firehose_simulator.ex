defmodule FirehoseSimulator do
  @moduledoc """
  The top-level API for the firehose simulator.
  """

  require Logger

  alias FirehoseSimulator.BulkCreation
  alias FirehoseSimulator.BulkCreation.Vacuum
  alias FirehoseSimulator.BaseData.UserbaseExport
  alias FirehoseSimulator.BaseData.UserbaseImport
  alias FirehoseSimulator.DatabaseConnection
  alias FirehoseSimulator.Player
  alias FirehoseSimulator.State
  alias FirehoseSimulator.Scenario
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

  @spec export_userbase_to_csv(String.t()) :: {:ok, map()} | {:error, String.t()}
  def export_userbase_to_csv(path) when is_binary(path) do
    export_userbase_to_csv(path, UserbaseExport.default_export_root())
  end

  @spec export_userbase_to_csv(String.t(), String.t()) :: {:ok, map()} | {:error, String.t()}
  def export_userbase_to_csv(path, export_dir)
      when is_binary(path) and is_binary(export_dir) do
    export_userbase_to_csv(path, export_dir, [])
  end

  @spec export_userbase_to_csv(String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, String.t()}
  def export_userbase_to_csv(path, export_dir, opts)
      when is_binary(path) and is_binary(export_dir) and is_list(opts) do
    with {:ok, userbase} <- load_userbase(path),
         {:ok, result} <- do_export_userbase_to_csv(userbase, export_dir, opts) do
      {:ok, result}
    end
  end

  @spec import_userbase_from_csv(String.t()) :: {:ok, map()} | {:error, String.t()}
  def import_userbase_from_csv(meta_path) when is_binary(meta_path) do
    import_userbase_from_csv(meta_path, database_connection())
  end

  @spec import_userbase_from_csv(String.t(), DatabaseConnection.t()) ::
          {:ok, map()} | {:error, String.t()}
  def import_userbase_from_csv(meta_path, %DatabaseConnection{} = connection)
      when is_binary(meta_path) do
    do_import_userbase_from_csv(meta_path, connection)
  end

  @spec import_userbase_from_csv(String.t(), String.t()) :: {:ok, map()} | {:error, String.t()}
  def import_userbase_from_csv(meta_path, connection_string)
      when is_binary(meta_path) and is_binary(connection_string) do
    import_userbase_from_csv(meta_path, %DatabaseConnection{connection_string: connection_string})
  end

  @spec bulk_create_scenario(Scenario.t()) :: {:ok, map()} | {:error, String.t()}
  def bulk_create_scenario(%Scenario{} = scenario) do
    bulk_create_scenario(scenario, database_connection())
  end

  @spec bulk_create_scenario(Scenario.t(), DatabaseConnection.t()) ::
          {:ok, map()} | {:error, String.t()}
  def bulk_create_scenario(
        %Scenario{} = scenario,
        %DatabaseConnection{} = connection
      ) do
    Logger.info("creating scenario data in database")

    case BulkCreation.create_scenario(scenario, connection) do
      {:ok, result} = ok ->
        Logger.info("created scenario data: #{inspect(result)}")
        ok

      {:error, reason} = error ->
        Logger.error("failed to create scenario data: #{reason}")
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

  defp do_export_userbase_to_csv(userbase, export_dir, opts) do
    Logger.info("exporting userbase #{userbase.name} to csv under #{export_dir}")

    case UserbaseExport.export(userbase, export_dir, opts) do
      {:ok, result} = ok ->
        Logger.info("exported userbase \"#{userbase.name}\": #{inspect(result)}")
        ok

      {:error, reason} = error ->
        Logger.error("failed to export userbase #{userbase.name}: #{reason}")
        error
    end
  end

  defp do_import_userbase_from_csv(meta_path, connection) do
    Logger.info("importing userbase from csv manifest #{meta_path}")

    case UserbaseImport.import(meta_path, connection) do
      {:ok, result} = ok ->
        Logger.info("imported userbase from csv manifest #{meta_path}: #{inspect(result)}")
        ok

      {:error, reason} = error ->
        Logger.error("failed to import userbase from csv manifest #{meta_path}: #{reason}")
        error
    end
  end

  # Scenario

  @spec generate_scenario_from_json(String.t()) ::
          {:ok, Scenario.t()} | {:error, String.t()}
  def generate_scenario_from_json(path) when is_binary(path) do
    generate_scenario_from_json(scenario_params: path)
  end

  @spec generate_scenario_from_json(keyword(String.t())) ::
          {:ok, Scenario.t()} | {:error, String.t()}
  def generate_scenario_from_json(opts) do
    Logger.info("generating scenario from params json file: #{inspect(opts)}")

    case Scenario.generate_from_json(opts) do
      {:ok, scenario} ->
        Logger.info("generated scenario sections")
        {:ok, scenario}

      {:error, reason} ->
        Logger.error("failed to generate scenario from json: #{reason}")
        {:error, reason}
    end
  end

  @spec import_scenario_from_json(String.t()) ::
          {:ok, Scenario.t()} | {:error, String.t()}
  def import_scenario_from_json(path) when is_binary(path) do
    Logger.info("importing scenario from json file: #{path}")
    Scenario.from_json_file(path)
  end

  @spec export_scenario_to_json(Scenario.t(), String.t()) ::
          :ok | {:error, String.t()}
  def export_scenario_to_json(%Scenario{} = scenario, path)
      when is_binary(path) do
    with {:ok, json} <- Scenario.to_json(scenario),
         :ok <- File.write(path, json) do
      :ok
    else
      {:error, reason} when is_binary(reason) -> {:error, reason}
      {:error, reason} -> {:error, "failed to write scenario json: #{inspect(reason)}"}
    end
  end

  @spec shift_scenario(Scenario.t(), integer()) :: Scenario.t()
  def shift_scenario(%Scenario{} = scenario, offset_ms)
      when is_integer(offset_ms) do
    Scenario.shift(scenario, offset_ms)
  end

  # Player

  @spec play(Scenario.t(), keyword()) :: {:ok, String.t(), map()} | {:error, term()}
  def play(%Scenario{} = scenario, opts \\ []) do
    Logger.info("starting simulation playback")

    case Player.play(scenario, opts) do
      {:ok, _player_id, _result} = ok ->
        Logger.info("simulation playback started")
        ok

      {:error, reason} = error ->
        Logger.error("failed to start simulation playback: #{inspect(reason)}")
        error
    end
  end

  @spec play_with_offset(Scenario.t(), integer()) ::
          {:ok, String.t(), map()} | {:error, term()}
  def play_with_offset(%Scenario{} = scenario, offset_ms)
      when is_integer(offset_ms) do
    play_with_offset(scenario, offset_ms, [])
  end

  @spec play_with_offset(Scenario.t(), integer(), keyword()) ::
          {:ok, String.t(), map()} | {:error, term()}
  def play_with_offset(%Scenario{} = scenario, offset_ms, opts)
      when is_integer(offset_ms) and is_list(opts) do
    scenario
    |> shift_scenario(offset_ms)
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
