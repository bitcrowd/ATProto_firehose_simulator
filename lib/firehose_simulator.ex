defmodule FirehoseSimulator do
  @moduledoc """
  The top-level API for the firehose simulator.
  """

  require Logger

  alias FirehoseSimulator.BaseData.Userbase
  alias FirehoseSimulator.BaseData.UserbaseExport
  alias FirehoseSimulator.BaseData.UserbaseImport
  alias FirehoseSimulator.BulkCreation
  alias FirehoseSimulator.BulkCreation.Vacuum
  alias FirehoseSimulator.Player
  alias FirehoseSimulator.RunStorage
  alias FirehoseSimulator.Scenario
  alias FirehoseSimulator.SimulationPlan
  alias FirehoseSimulator.State

  @spec create_userbase() :: {:ok, map()} | {:error, String.t()}
  def create_userbase do
    create_userbase(userbase_filename())
  end

  @spec create_userbase(String.t()) :: {:ok, map()} | {:error, String.t()}
  def create_userbase(path) when is_binary(path) do
    with {:ok, json} <- read_userbase_file(path) do
      create_userbase_from_json(json)
    end
  end

  @spec create_userbase_from_json(String.t()) :: {:ok, map()} | {:error, String.t()}
  def create_userbase_from_json(json) when is_binary(json) do
    with {:ok, userbase} <- load_userbase_json(json),
         :ok <- maybe_store_userbase_json(json) do
      do_create_userbase(userbase)
    end
  end

  @spec export_userbase_to_csv(String.t()) :: {:ok, map()} | {:error, String.t()}
  def export_userbase_to_csv(path) when is_binary(path) do
    with {:ok, run_directory} <- run_storage_directory(),
         {:ok, export_root} <- RunStorage.default_userbase_export_root(run_directory) do
      export_userbase_to_csv(path, export_root)
    end
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
    with {:ok, json} <- read_userbase_file(path) do
      export_userbase_to_csv_from_json(json, export_dir, opts)
    end
  end

  @spec export_userbase_to_csv_from_json(String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, String.t()}
  def export_userbase_to_csv_from_json(json, export_dir, opts \\ [])
      when is_binary(json) and is_binary(export_dir) and is_list(opts) do
    with {:ok, userbase} <- load_userbase_json(json) do
      do_export_userbase_to_csv(userbase, export_dir, opts)
    end
  end

  @spec import_userbase_from_csv(String.t()) :: {:ok, map()} | {:error, String.t()}
  def import_userbase_from_csv(meta_path) when is_binary(meta_path) do
    with {:ok, meta_json} <- read_userbase_manifest_file(meta_path),
         {:ok, result} <- import_userbase_from_csv_json(meta_json) do
      {:ok, Map.put(result, :meta_path, meta_path)}
    end
  end

  @spec import_userbase_from_csv_json(String.t(), keyword()) ::
          {:ok, map()} | {:error, String.t()}
  def import_userbase_from_csv_json(meta_json, opts \\ [])
      when is_binary(meta_json) and is_list(opts) do
    repo = Keyword.get(opts, :repo, FirehoseSimulator.Repo)
    import_opts = Keyword.drop(opts, [:repo])

    with {:ok, result} <- do_import_userbase_from_csv_json(meta_json, repo, import_opts),
         {:ok, stored_path} <- maybe_store_userbase_manifest_json(meta_json) do
      {:ok, Map.put(result, :run_userbase_meta_path, stored_path)}
    end
  end

  @spec bulk_create_scenario(Scenario.t()) :: {:ok, map()}
  def bulk_create_scenario(%Scenario{} = scenario) do
    Logger.info("creating scenario data in database")

    {:ok, result} = BulkCreation.create_scenario(scenario)
    Logger.info("created scenario data: #{inspect(result)}")

    {:ok, result}
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

  @spec generate_scenario_from_json(String.t()) ::
          {:ok, Scenario.t()} | {:error, String.t()}
  def generate_scenario_from_json(path) when is_binary(path) do
    with {:ok, json} <- read_scenario_params_file(path) do
      generate_scenario_from_json_string(json, name: scenario_name_from_path(path))
    end
  end

  @spec generate_scenario_from_json_string(String.t(), keyword()) ::
          {:ok, Scenario.t()} | {:error, String.t()}
  def generate_scenario_from_json_string(json, opts \\ [])
      when is_binary(json) and is_list(opts) do
    Logger.info("generating scenario from params json content")
    scenario_name = Keyword.get(opts, :name)

    with {:ok, scenario} <- Scenario.generate_from_json_string(json),
         {:ok, scenario} <-
           maybe_persist_generated_scenario(scenario, json, scenario_name) do
      Logger.info("generated scenario sections")
      {:ok, scenario}
    else
      {:error, reason} ->
        Logger.error("failed to generate scenario from json: #{reason}")
        {:error, reason}
    end
  end

  @spec import_scenario_from_json(String.t()) ::
          {:ok, Scenario.t()} | {:error, String.t()}
  def import_scenario_from_json(path) when is_binary(path) do
    Logger.info("importing scenario from json file: #{path}")

    with {:ok, json} <- read_scenario_file(path) do
      import_scenario_from_json_string(
        json,
        name: scenario_name_from_path(path),
        source_path: path
      )
    end
  end

  @spec import_scenario_from_json_string(String.t(), keyword()) ::
          {:ok, Scenario.t()} | {:error, String.t()}
  def import_scenario_from_json_string(json, opts \\ [])
      when is_binary(json) and is_list(opts) do
    scenario_name = Keyword.get(opts, :name)
    source_path = Keyword.get(opts, :source_path)

    with {:ok, scenario} <- Scenario.from_json(json) do
      maybe_persist_imported_scenario(scenario, scenario_name, source_path)
    end
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
        DateTime.diff(DateTime.utc_now(), current_plan.started_at, :millisecond)
      else
        0
      end

    with {:ok, simulation_plan, imported_entries} <-
           SimulationPlan.JSON.import_from_json(path, current_plan, offset_ms),
         {:ok, simulation_plan} <- maybe_localize_simulation_plan(simulation_plan),
         imported_entries <-
           localize_imported_entries(imported_entries, simulation_plan, current_plan),
         {past_entries, future_entries} <- split_past_and_future_entries(imported_entries),
         :ok <- bulk_create_entries(past_entries, offset_ms),
         :ok <- load_entries(future_entries, offset_ms),
         {:ok, updated_plan} <- maybe_persist_simulation_plan(simulation_plan) do
      :ok = State.put_simulation_plan(updated_plan)
      {:ok, updated_plan}
    else
      {:error, reason} = error ->
        Logger.error("failed to import simulation plan from json #{path}: #{inspect(reason)}")
        error
    end
  end

  defp localize_imported_entries(imported_entries, simulation_plan, current_plan) do
    localized_entries = Enum.drop(simulation_plan.entries, length(current_plan.entries))

    Enum.zip_with(imported_entries, localized_entries, fn imported_entry, localized_entry ->
      %{preload?: imported_entry.preload?, entry: localized_entry}
    end)
  end

  defp split_past_and_future_entries(entries) do
    {past_entries, future_entries} = Enum.split_with(entries, & &1.preload?)
    {Enum.map(past_entries, & &1.entry), Enum.map(future_entries, & &1.entry)}
  end

  defp load_entries(entries, offset_ms) do
    Enum.reduce_while(entries, :ok, fn entry, :ok ->
      case load_entry(entry, offset_ms) do
        {:ok, _} -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp load_entry(entry, import_offset_ms) do
    total_offset_ms = entry.offset_ms + import_offset_ms

    case FirehoseSimulator.load_with_offset(
           entry.scenario,
           total_offset_ms,
           scenario_id: entry.scenario_name
         ) do
      {:ok, player_id, metadata} ->
        metadata =
          metadata
          |> Map.put(:scenario_name, entry.scenario_name)
          |> Map.put(:scenario_path, entry.scenario_path)
          |> Map.put(:offset_ms, entry.offset_ms)

        {:ok, %{player_id: player_id, metadata: metadata, entry: entry}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp bulk_create_entries(entries, offset_ms) do
    Enum.each(entries, &bulk_create_entry(&1, offset_ms))
    :ok
  end

  defp bulk_create_entry(entry, offset_ms) do
    Logger.info(
      "bulk creating imported scenario #{entry.scenario_name} from #{entry.scenario_path}"
    )

    {:ok, result} = bulk_create_scenario(entry.scenario)

    {:ok,
     %{
       entry: entry,
       offset_ms: offset_ms,
       result: result
     }}
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

    with {:ok, scenario_path, scenario} <-
           ensure_scenario_path(scenario, scenario_path, scenario_name),
         {:ok, simulation_plan, entry} <-
           SimulationPlan.add_scenario(
             current_plan,
             scenario,
             scenario_name,
             submitted_offset_ms,
             scenario_path
           ),
         {:ok, simulation_plan} <- maybe_persist_simulation_plan(simulation_plan) do
      :ok = State.put_simulation_plan(simulation_plan)
      {:ok, scenario} = Scenario.put_source_path(scenario, entry.scenario_path)
      :ok = State.put_scenario(scenario_name, scenario)
      {:ok, simulation_plan}
    end
  end

  defp ensure_scenario_path(%Scenario{} = scenario, scenario_path, scenario_name)
       when is_binary(scenario_path) do
    case normalize_path(scenario_path) do
      nil ->
        ensure_scenario_path(scenario, nil, scenario_name)

      path ->
        if run_storage_enabled?() do
          export_generated_scenario(scenario, scenario_name)
        else
          put_scenario_path(scenario, path)
        end
    end
  end

  defp ensure_scenario_path(%Scenario{} = scenario, _scenario_path, scenario_name) do
    if run_storage_enabled?() do
      export_generated_scenario(scenario, scenario_name)
    else
      path = scenario.source_path || dummy_scenario_path(scenario_name)

      put_scenario_path(scenario, path)
    end
  end

  defp export_generated_scenario(%Scenario{} = scenario, scenario_name) do
    with {:ok, run_directory} <- run_storage_directory(),
         {:ok, path} <- RunStorage.store_scenario(run_directory, scenario, scenario_name),
         {:ok, scenario} <- Scenario.put_source_path(scenario, path) do
      {:ok, path, scenario}
    end
  end

  defp userbase_filename do
    Application.fetch_env!(:firehose_simulator, :default_userbase_json_path)
  end

  defp load_userbase_json(json) do
    Logger.info("loading userbase from json content")

    case Userbase.load(json) do
      {:ok, userbase} ->
        Logger.info("loaded userbase #{userbase.name} with #{userbase.num_users} users")
        {:ok, userbase}

      {:error, reason} ->
        Logger.error("failed to load userbase from json: #{reason}")
        {:error, reason}
    end
  end

  defp read_userbase_file(path) do
    Logger.info("loading userbase from #{path}")

    case File.read(path) do
      {:ok, json} -> {:ok, json}
      {:error, _reason} -> {:error, "cannot read userbase file at #{path}"}
    end
  end

  defp read_userbase_manifest_file(path) do
    Logger.info("importing userbase from csv manifest #{path}")

    case File.read(path) do
      {:ok, json} -> {:ok, json}
      {:error, _reason} -> {:error, "cannot read userbase meta file at #{path}"}
    end
  end

  defp read_scenario_params_file(path) do
    Logger.info("generating scenario from params json file: #{path}")

    case File.read(path) do
      {:ok, json} ->
        {:ok, json}

      {:error, :enoent} ->
        {:error, "cannot read scenario params file at #{path}"}

      {:error, reason} ->
        {:error, "failed to read scenario params file #{path}: #{inspect(reason)}"}
    end
  end

  defp read_scenario_file(path) do
    case File.read(path) do
      {:ok, json} -> {:ok, json}
      {:error, :enoent} -> {:error, "cannot read scenario json at #{path}"}
      {:error, reason} -> {:error, "failed to read scenario json #{path}: #{inspect(reason)}"}
    end
  end

  defp do_create_userbase(userbase) do
    Logger.info("creating userbase #{userbase.name} in database for #{userbase.num_users} users")

    {:ok, result} = BulkCreation.create_userbase(userbase)
    Logger.info("created userbase \"#{userbase.name}\": #{inspect(result)}")
    {:ok, result}
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

  defp do_import_userbase_from_csv_json(meta_json, repo, opts) do
    Logger.info("importing userbase from csv manifest json")

    case UserbaseImport.import_from_meta_json(meta_json, repo, opts) do
      {:ok, result} = ok ->
        Logger.info("imported userbase from csv manifest json: #{inspect(result)}")
        ok

      {:error, reason} = error ->
        Logger.error("failed to import userbase from csv manifest json: #{reason}")
        error
    end
  end

  defp scenario_name_from_path(path) when is_binary(path) do
    path
    |> Path.basename()
    |> Path.rootname()
  end

  defp run_storage_directory do
    case State.get_run_storage_directory() do
      nil -> {:error, "run storage is disabled; provide an export directory explicitly"}
      run_directory -> {:ok, run_directory}
    end
  end

  defp maybe_persist_generated_scenario(%Scenario{} = scenario, json, scenario_name) do
    if run_storage_enabled?() do
      with {:ok, run_directory} <- run_storage_directory(),
           {:ok, _params_copy} <-
             RunStorage.store_scenario_params_json(run_directory, json, name: scenario_name),
           {:ok, scenario_path} <-
             RunStorage.store_scenario(run_directory, scenario, scenario_name) do
        Scenario.put_source_path(scenario, scenario_path)
      end
    else
      Scenario.put_source_path(scenario, dummy_scenario_path(scenario_name))
    end
  end

  defp maybe_persist_imported_scenario(%Scenario{} = scenario, scenario_name, source_path) do
    if run_storage_enabled?() do
      with {:ok, run_directory} <- run_storage_directory(),
           {:ok, scenario_path} <-
             RunStorage.store_scenario(run_directory, scenario, scenario_name) do
        Scenario.put_source_path(scenario, scenario_path)
      end
    else
      Scenario.put_source_path(
        scenario,
        normalize_path(source_path) || scenario.source_path ||
          dummy_scenario_path(scenario_name)
      )
    end
  end

  defp maybe_localize_simulation_plan(%SimulationPlan{} = simulation_plan) do
    if run_storage_enabled?() do
      with {:ok, run_directory} <- run_storage_directory() do
        RunStorage.localize_plan_entries(run_directory, simulation_plan)
      end
    else
      {:ok, simulation_plan}
    end
  end

  defp maybe_persist_simulation_plan(%SimulationPlan{} = simulation_plan) do
    if run_storage_enabled?() do
      with {:ok, run_directory} <- run_storage_directory(),
           {:ok, export_path} <-
             RunStorage.persist_simulation_plan(run_directory, simulation_plan) do
        SimulationPlan.update(
          simulation_plan,
          simulation_plan_attrs(simulation_plan, export_path)
        )
      end
    else
      SimulationPlan.update(simulation_plan, simulation_plan_attrs(simulation_plan, nil))
    end
  end

  defp simulation_plan_attrs(%SimulationPlan{} = simulation_plan, export_path) do
    %{
      name: simulation_plan.name,
      started_at: simulation_plan.started_at,
      export_path: export_path,
      entries: simulation_plan.entries
    }
  end

  defp maybe_store_userbase_json(json) when is_binary(json) do
    if run_storage_enabled?() do
      with {:ok, run_directory} <- run_storage_directory(),
           {:ok, _stored_path} <- RunStorage.store_userbase_json(run_directory, json) do
        :ok
      end
    else
      :ok
    end
  end

  defp maybe_store_userbase_manifest_json(meta_json) when is_binary(meta_json) do
    if run_storage_enabled?() do
      case run_storage_directory() do
        {:ok, run_directory} ->
          RunStorage.store_userbase_manifest_json(run_directory, meta_json)

        {:error, _reason} = error ->
          error
      end
    else
      {:ok, nil}
    end
  end

  defp run_storage_enabled? do
    Application.get_env(:firehose_simulator, :run_storage_enabled, true)
  end

  defp normalize_path(path) when is_binary(path) do
    case String.trim(path) do
      "" -> nil
      value -> value
    end
  end

  defp normalize_path(_path), do: nil

  defp dummy_scenario_path(scenario_name) do
    "dummy://scenarios/#{scenario_name}-#{System.unique_integer([:positive, :monotonic])}.json"
  end

  defp put_scenario_path(%Scenario{} = scenario, path) do
    with {:ok, scenario} <- Scenario.put_source_path(scenario, path) do
      {:ok, path, scenario}
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

  @spec status(String.t()) :: map() | {:error, term()}
  def status(player_id) when is_binary(player_id), do: Player.status(player_id)
end
