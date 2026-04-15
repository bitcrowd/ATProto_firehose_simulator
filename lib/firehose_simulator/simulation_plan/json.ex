defmodule FirehoseSimulator.SimulationPlan.JSON do
  @moduledoc false

  alias FirehoseSimulator.Scenario
  alias FirehoseSimulator.SimulationPlan
  alias FirehoseSimulator.SimulationPlan.Entry

  @default_export_dir "log"

  @spec encode(SimulationPlan.t()) :: {:ok, String.t()} | {:error, String.t()}
  def encode(%SimulationPlan{} = simulation_plan) do
    attrs = %{
      name: simulation_plan.name,
      entries:
        Enum.map(simulation_plan.entries, fn entry ->
          %{
            scenario_name: entry.scenario_name,
            scenario_path: entry.scenario_path,
            offset_ms: entry.offset_ms
          }
        end)
    }

    case Jason.encode(attrs) do
      {:ok, json} -> {:ok, json}
      {:error, reason} -> {:error, "failed to encode simulation plan json: #{inspect(reason)}"}
    end
  end

  @spec decode(String.t()) :: {:ok, SimulationPlan.t()} | {:error, String.t()}
  def decode(json) when is_binary(json) do
    with {:ok, attrs} <- decode_object(json),
         {:ok, simulation_plan} <- SimulationPlan.new(attrs) do
      {:ok, simulation_plan}
    end
  end

  defp decode_object(json) do
    case Jason.decode(json) do
      {:ok, %{} = attrs} -> {:ok, attrs}
      {:ok, _other} -> {:error, "invalid simulation plan json: expected json object"}
      {:error, _reason} -> {:error, "invalid simulation plan json"}
    end
  end

  @spec import_from_json(String.t(), SimulationPlan.t(), integer()) ::
          {:ok, SimulationPlan.t(), [Entry.t()]} | {:error, String.t()}
  def import_from_json(path, %SimulationPlan{} = simulation_plan, offset_ms)
      when is_binary(path) do
    base_dir = Path.dirname(Path.expand(path))

    with {:ok, json} <- File.read(path),
         {:ok, decoded_plan} <- decode(json),
         {:ok, imported_entry_attrs} <-
           load_imported_entry_attrs(decoded_plan, base_dir, offset_ms),
         {:ok, updated_plan} <-
           merge_imported_entry_attrs(simulation_plan, decoded_plan.name, imported_entry_attrs) do
      imported_entries = Enum.drop(updated_plan.entries, length(simulation_plan.entries))
      {:ok, updated_plan, imported_entries}
    else
      {:error, :enoent} -> {:error, "cannot read simulation plan json at #{path}"}
      {:error, reason} when is_binary(reason) -> {:error, reason}
      {:error, reason} -> {:error, "failed to import simulation plan json: #{inspect(reason)}"}
    end
  end

  @spec export_to_file(SimulationPlan.t(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def export_to_file(%SimulationPlan{} = simulation_plan, path \\ nil) do
    path = path || Path.join(@default_export_dir, timestamped_filename("simulation_plan", "json"))

    with {:ok, json} <- encode(simulation_plan),
         :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(path, json) do
      {:ok, path}
    else
      {:error, reason} when is_binary(reason) -> {:error, reason}
      {:error, reason} -> {:error, "failed to export simulation plan json: #{inspect(reason)}"}
    end
  end

  @spec timestamped_filename(String.t(), String.t()) :: String.t()
  def timestamped_filename(base, extension) do
    timestamp = DateTime.utc_now() |> Calendar.strftime("%Y%m%dT%H%M%SZ")
    unique = System.unique_integer([:positive, :monotonic])
    "#{timestamp}_#{base}_#{unique}.#{extension}"
  end

  defp load_imported_entry_attrs(%SimulationPlan{} = plan, base_dir, import_offset_ms) do
    Enum.reduce_while(plan.entries, {:ok, []}, fn entry, {:ok, acc} ->
      resolved_scenario_path = resolve_scenario_path(base_dir, entry.scenario_path)

      case Scenario.from_json_file(resolved_scenario_path) do
        {:ok, scenario} ->
          entry_attrs = %{
            "scenario_name" => entry.scenario_name,
            "scenario_path" => scenario.source_path,
            "offset_ms" => import_offset_ms + entry.offset_ms,
            "scenario" => scenario
          }

          {:cont, {:ok, [entry_attrs | acc]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, entries} -> {:ok, Enum.reverse(entries)}
      {:error, _reason} = error -> error
    end
  end

  defp merge_imported_entry_attrs(
         %SimulationPlan{} = simulation_plan,
         imported_plan_name,
         imported_entry_attrs
       ) do
    attrs = %{
      name: simulation_plan.name || imported_plan_name,
      started_at: simulation_plan.started_at,
      export_path: simulation_plan.export_path,
      entries: simulation_plan.entries ++ imported_entry_attrs
    }

    simulation_plan
    |> SimulationPlan.changeset(attrs)
    |> Ecto.Changeset.apply_action(:insert)
    |> case do
      {:ok, %SimulationPlan{} = updated_plan} ->
        {:ok, updated_plan}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, format_changeset_errors(changeset)}
    end
  end

  defp resolve_scenario_path(base_dir, path) do
    if Path.type(path) == :absolute do
      path
    else
      Path.expand(path, base_dir)
    end
  end

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)
    |> Enum.map(fn {field, messages} -> "#{field} #{Enum.join(messages, ", ")}" end)
    |> Enum.join("; ")
  end
end
