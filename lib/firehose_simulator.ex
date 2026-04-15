defmodule FirehoseSimulator do
  @moduledoc """
  The top-level API for the firehose simulator.
  """

  require Logger

  alias FirehoseSimulator.BulkCreation
  alias FirehoseSimulator.BulkCreation.Vacuum
  alias FirehoseSimulator.BaseData.UserbaseExport
  alias FirehoseSimulator.BaseData.UserbaseImport
  alias FirehoseSimulator.Player
  alias FirehoseSimulator.Scenario
  alias FirehoseSimulator.SimulationPlan
  alias FirehoseSimulator.State
  alias FirehoseSimulator.BaseData.Userbase

  @default_userbase_filename "priv/simulation/userbase.json"

  # Bulk Creation
  @spec create_userbase() :: {:ok, map()} | {:error, String.t()}
  def create_userbase do
    create_userbase(userbase_filename())
  end

  @spec create_userbase(String.t()) :: {:ok, map()} | {:error, String.t()}
  def create_userbase(path) when is_binary(path) do
    with {:ok, userbase} <- load_userbase(path),
         {:ok, result} <- do_create_userbase(userbase) do
      {:ok, result}
    end
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
    do_import_userbase_from_csv(meta_path)
  end

  @spec bulk_create_scenario(Scenario.t()) :: {:ok, map()} | {:error, String.t()}
  def bulk_create_scenario(%Scenario{} = scenario) do
    Logger.info("creating scenario data in database")

    case BulkCreation.create_scenario(scenario) do
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
    Logger.info("running vacuum actions")

    case Vacuum.run(opts) do
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

  defp do_create_userbase(userbase) do
    Logger.info("creating userbase #{userbase.name} in database for #{userbase.num_users} users")

    case BulkCreation.create_userbase(userbase) do
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

  defp do_import_userbase_from_csv(meta_path) do
    Logger.info("importing userbase from csv manifest #{meta_path}")

    case UserbaseImport.import(meta_path) do
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
         :ok <- File.mkdir_p(Path.dirname(path)),
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

  # Simulation Plan

  @spec import_simulation_plan_from_json(String.t()) ::
          {:ok, SimulationPlan.t()} | {:error, String.t() | term()}
  def import_simulation_plan_from_json(path) when is_binary(path) do
    Logger.info("importing simulation plan from json file: #{path}")

    current_plan = State.get_simulation_plan()

    offset_ms =
      if current_plan.started_at do
        DateTime.diff(DateTime.utc_now(), current_plan.started_at, :milllisecond)
      else
        0
      end

    with {:ok, simulation_plan, imported_entries} <-
           SimulationPlan.JSON.import_from_json(path, current_plan, offset_ms),
         {:ok, _played_entries} <-
           SimulationPlan.load_entries(imported_entries, offset_ms) do
      :ok = State.put_simulation_plan(simulation_plan)
      {:ok, simulation_plan}
    else
      {:error, reason} = error ->
        Logger.error("failed to import simulation plan from json #{path}: #{inspect(reason)}")
        error
    end
  end

  @spec export_simulation_plan_to_json(SimulationPlan.t(), String.t()) ::
          :ok | {:error, String.t()}
  def export_simulation_plan_to_json(%SimulationPlan{} = simulation_plan, path)
      when is_binary(path) do
    case SimulationPlan.JSON.export_to_file(simulation_plan, path) do
      {:ok, _path} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @spec current_simulation_plan() :: SimulationPlan.t()
  def current_simulation_plan do
    State.get_simulation_plan()
  end

  @spec add_and_play_scenario(String.t(), Scenario.t(), integer(), String.t()) ::
          {:ok, SimulationPlan.t()} | {:error, String.t()}
  def add_and_play_scenario(
        scenario_name,
        %Scenario{} = scenario,
        submitted_offset_ms,
        scenario_path
      )
      when is_binary(scenario_name) and is_integer(submitted_offset_ms) do
    current_plan = State.get_simulation_plan()

    with {:ok, scenario_path, scenario} <- ensure_scenario_path(scenario, scenario_path),
         {:ok, simulation_plan, entry} <-
           SimulationPlan.add_scenario(
             current_plan,
             scenario,
             scenario_name,
             submitted_offset_ms,
             scenario_path
           ),
         {:ok, export_path} <-
           SimulationPlan.JSON.export_to_file(simulation_plan) do
      simulation_plan = %{simulation_plan | export_path: export_path}
      :ok = State.put_simulation_plan(simulation_plan)
      :ok = State.put_scenario(scenario_name, %{scenario | source_path: entry.scenario_path})
      {:ok, simulation_plan}
    end
  end

  defp ensure_scenario_path(%Scenario{} = scenario, scenario_path)
       when is_binary(scenario_path) do
    case String.trim(scenario_path) do
      "" -> export_generated_scenario(scenario)
      path -> {:ok, path, %{scenario | source_path: path}}
    end
  end

  defp ensure_scenario_path(%Scenario{} = scenario, _scenario_path),
    do: export_generated_scenario(scenario)

  defp export_generated_scenario(%Scenario{} = scenario) do
    path =
      Path.join(
        System.tmp_dir!(),
        "firehose-scenario-#{System.unique_integer([:positive])}.json"
      )

    case export_scenario_to_json(scenario, path) do
      :ok -> {:ok, path, %{scenario | source_path: path}}
      {:error, reason} -> {:error, reason}
    end
  end

  # Player

  @spec load(Scenario.t(), keyword()) :: {:ok, String.t(), map()} | {:error, term()}
  def load(%Scenario{} = scenario, opts \\ []) do
    Logger.info("loading simulation player")

    case Player.load(scenario, opts) do
      {:ok, _player_id, _result} = ok ->
        Logger.info("simulation player loaded")
        ok

      {:error, reason} = error ->
        Logger.error("failed to load simulation player: #{inspect(reason)}")
        error
    end
  end

  @spec load_with_offset(Scenario.t(), integer()) ::
          {:ok, String.t(), map()} | {:error, term()}
  def load_with_offset(%Scenario{} = scenario, offset_ms)
      when is_integer(offset_ms) do
    load_with_offset(scenario, offset_ms, [])
  end

  @spec load_with_offset(Scenario.t(), integer(), keyword()) ::
          {:ok, String.t(), map()} | {:error, term()}
  def load_with_offset(%Scenario{} = scenario, offset_ms, opts)
      when is_integer(offset_ms) and is_list(opts) do
    scenario
    |> shift_scenario(offset_ms)
    |> load(opts)
  end

  @spec start(String.t()) :: :ok | {:error, term()}
  def start(player_id) when is_binary(player_id) do
    Logger.info("starting simulation playback for #{player_id}")

    case Player.start(player_id) do
      :ok ->
        Logger.info("simulation playback started for #{player_id}")
        :ok

      {:error, reason} = error ->
        Logger.error("failed to start simulation playback for #{player_id}: #{inspect(reason)}")
        error
    end
  end

  @spec pause(String.t()) :: :ok | {:error, term()}
  def pause(player_id) when is_binary(player_id) do
    Logger.info("pausing simulation playback for #{player_id}")

    case Player.pause(player_id) do
      :ok ->
        Logger.info("simulation playback paused for #{player_id}")
        :ok

      {:error, reason} = error ->
        Logger.error("failed to pause simulation playback for #{player_id}: #{inspect(reason)}")
        error
    end
  end

  @spec stop(String.t()) :: :ok | {:error, term()}
  def stop(player_id) when is_binary(player_id) do
    Logger.info("stopping simulation playback")

    case Player.stop(player_id) do
      :ok ->
        Logger.info("simulation playback stopped for #{player_id}")
        :ok

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
