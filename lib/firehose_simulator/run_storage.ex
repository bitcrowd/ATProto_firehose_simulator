defmodule FirehoseSimulator.RunStorage do
  @moduledoc false

  alias FirehoseSimulator.Scenario
  alias FirehoseSimulator.SimulationPlan
  alias FirehoseSimulator.SimulationPlan.Entry
  alias FirehoseSimulator.Utils

  @default_runs_root "runs"
  @default_log_file "firehose_simulator.log"
  @run_subdirectories ~w(logs userbase scenario_params scenarios)

  @spec timestamped_directory() :: String.t()
  def timestamped_directory do
    Path.join(runs_root(), timestamped_run_dir_name())
  end

  @spec ensure_run_directory(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def ensure_run_directory(run_directory) when is_binary(run_directory) do
    directories =
      [run_directory | Enum.map(@run_subdirectories, &Path.join(run_directory, &1))]

    case ensure_directories(directories) do
      :ok ->
        {:ok, run_directory}

      {:error, {directory, reason}} ->
        {:error, "failed to create run storage directory #{directory}: #{inspect(reason)}"}
    end
  end

  @spec store_userbase_file(String.t(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def store_userbase_file(run_directory, path)
      when is_binary(run_directory) and is_binary(path) do
    copy_into_run(run_directory, path, "userbase", "userbase.json")
  end

  @spec store_userbase_json(String.t(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def store_userbase_json(run_directory, json)
      when is_binary(run_directory) and is_binary(json) do
    write_into_run(run_directory, json, "userbase", "userbase.json")
  end

  @spec store_userbase_manifest(String.t(), String.t()) ::
          {:ok, String.t()} | {:error, String.t()}
  def store_userbase_manifest(run_directory, path)
      when is_binary(run_directory) and is_binary(path) do
    copy_into_run(run_directory, path, "userbase", "userbase_meta.json")
  end

  @spec store_userbase_manifest_json(String.t(), String.t()) ::
          {:ok, String.t()} | {:error, String.t()}
  def store_userbase_manifest_json(run_directory, json)
      when is_binary(run_directory) and is_binary(json) do
    write_into_run(run_directory, json, "userbase", "userbase_meta.json")
  end

  @spec store_scenario_params(String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, String.t()}
  def store_scenario_params(run_directory, path, opts \\ [])
      when is_binary(run_directory) and is_binary(path) and is_list(opts) do
    filename = build_filename(path, Keyword.get(opts, :name), ".json")
    copy_into_run(run_directory, path, "scenario_params", filename)
  end

  @spec store_scenario_params_json(String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, String.t()}
  def store_scenario_params_json(run_directory, json, opts \\ [])
      when is_binary(run_directory) and is_binary(json) and is_list(opts) do
    filename = build_filename("scenario_params.json", Keyword.get(opts, :name), ".json")
    write_into_run(run_directory, json, "scenario_params", filename)
  end

  @spec store_scenario(String.t(), Scenario.t(), String.t() | nil) ::
          {:ok, String.t()} | {:error, String.t()}
  def store_scenario(run_directory, %Scenario{} = scenario, scenario_name \\ nil)
      when is_binary(run_directory) do
    with {:ok, json} <- Scenario.to_json(scenario) do
      file_name = build_filename("scenario.json", scenario_name, ".json")
      scenario_path = Path.join([run_directory, "scenarios", file_name])

      with :ok <- File.mkdir_p(Path.dirname(scenario_path)),
           :ok <- File.write(scenario_path, json) do
        {:ok, scenario_path}
      else
        {:error, reason} -> {:error, "failed to write scenario json: #{inspect(reason)}"}
      end
    end
  end

  @spec persist_simulation_plan(String.t(), SimulationPlan.t()) ::
          {:ok, String.t()} | {:error, String.t()}
  def persist_simulation_plan(run_directory, %SimulationPlan{} = simulation_plan)
      when is_binary(run_directory) do
    SimulationPlan.JSON.export_to_file(
      simulation_plan,
      Path.join(run_directory, "simulation_plan.json")
    )
  end

  @spec default_userbase_export_root(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def default_userbase_export_root(run_directory) when is_binary(run_directory) do
    {:ok, Path.join([run_directory, "userbase"])}
  end

  @spec default_log_file_path(String.t(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def default_log_file_path(run_directory, basename \\ @default_log_file)
      when is_binary(run_directory) and is_binary(basename) do
    {:ok, Path.join([run_directory, "logs", basename])}
  end

  @spec localize_plan_entries(String.t(), SimulationPlan.t()) ::
          {:ok, SimulationPlan.t()} | {:error, String.t()}
  def localize_plan_entries(run_directory, %SimulationPlan{} = simulation_plan)
      when is_binary(run_directory) do
    simulation_plan.entries
    |> Enum.reduce_while({:ok, []}, fn entry, {:ok, acc} ->
      case localize_entry(run_directory, entry) do
        {:ok, updated_entry} -> {:cont, {:ok, [updated_entry | acc]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, entries} ->
        SimulationPlan.update(simulation_plan, %{
          name: simulation_plan.name,
          started_at: simulation_plan.started_at,
          export_path: simulation_plan.export_path,
          entries: Enum.reverse(entries)
        })

      {:error, _reason} = error ->
        error
    end
  end

  defp localize_entry(
         run_directory,
         %Entry{scenario: %Scenario{} = scenario, scenario_name: scenario_name} = entry
       )
       when is_binary(run_directory) do
    with {:ok, scenario_path} <- store_scenario(run_directory, scenario, scenario_name),
         {:ok, scenario} <- Scenario.put_source_path(scenario, scenario_path) do
      Entry.update(entry, %{
        scenario_name: entry.scenario_name,
        scenario_path: scenario_path,
        offset_ms: entry.offset_ms,
        scenario: scenario
      })
    end
  end

  defp localize_entry(_run_directory, %Entry{} = entry), do: {:ok, entry}

  defp ensure_directories(directories) do
    Enum.reduce_while(directories, :ok, fn directory, :ok ->
      case File.mkdir_p(directory) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {directory, reason}}}
      end
    end)
  end

  defp copy_into_run(run_directory, source_path, directory, file_name) do
    destination = Path.join([run_directory, directory, file_name])

    with :ok <- File.mkdir_p(Path.dirname(destination)),
         :ok <- File.cp(source_path, destination) do
      {:ok, destination}
    else
      {:error, reason} ->
        {:error, "failed to copy #{source_path} to #{destination}: #{inspect(reason)}"}
    end
  end

  defp write_into_run(run_directory, content, directory, file_name) do
    destination = Path.join([run_directory, directory, file_name])

    with :ok <- File.mkdir_p(Path.dirname(destination)),
         :ok <- File.write(destination, content) do
      {:ok, destination}
    else
      {:error, reason} -> {:error, "failed to write #{destination}: #{inspect(reason)}"}
    end
  end

  defp runs_root do
    Application.get_env(:firehose_simulator, :runs_root, Path.expand(@default_runs_root))
  end

  defp timestamped_run_dir_name do
    timestamp = DateTime.utc_now() |> Calendar.strftime("%Y%m%dT%H%M%S.%f")
    "#{timestamp}"
  end

  defp build_filename(source_path, provided_name, extension) do
    base_name =
      case sanitize_name(provided_name) do
        nil -> sanitize_name(Path.rootname(Path.basename(source_path)))
        value -> value
      end

    "#{base_name || "artifact"}#{extension}"
  end

  defp sanitize_name(nil), do: nil

  defp sanitize_name(name) when is_binary(name) do
    Utils.slugify(name, nil)
  end
end
