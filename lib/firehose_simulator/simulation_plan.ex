defmodule FirehoseSimulator.SimulationPlan do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias FirehoseSimulator
  alias FirehoseSimulator.SimulationPlan
  alias FirehoseSimulator.SimulationPlan.Entry

  require Logger

  @primary_key false
  embedded_schema do
    field(:name, :string)
    field(:started_at, :utc_datetime_usec)
    field(:export_path, :string)
    embeds_many(:entries, Entry, on_replace: :delete)
  end

  @type t :: %__MODULE__{
          name: String.t() | nil,
          started_at: DateTime.t() | nil,
          export_path: String.t() | nil,
          entries: [Entry.t()]
        }

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(simulation_plan, attrs) do
    simulation_plan
    |> cast(attrs, [:name, :started_at, :export_path])
    |> cast_embed(:entries, with: &Entry.changeset/2)
  end

  @spec new(map()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def new(attrs \\ %{}) when is_map(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> apply_action(:insert)
  end

  @spec add_scenario(SimulationPlan.t(), Scenario.t(), String.t(), integer(), String.t()) ::
          {:ok, SimulationPlan.t(), Entry.t()} | {:error, String.t()}
  def add_scenario(
        %SimulationPlan{} = simulation_plan,
        scenario,
        scenario_name,
        offset_ms,
        scenario_path
      ) do
    total_offset_ms =
      if simulation_plan.started_at do
        DateTime.diff(DateTime.utc_now(), simulation_plan.started_at, :millisecond) + offset_ms
      else
        offset_ms
      end

    with {:ok, entry} <-
           Entry.new(%{
             scenario_name: scenario_name,
             scenario: scenario,
             scenario_path: scenario_path,
             offset_ms: total_offset_ms
           }) do
      {:ok, %{simulation_plan | entries: simulation_plan.entries ++ [entry]}, entry}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, format_changeset_errors(changeset)}
    end
  end

  @spec load_entries([Entry.t()], integer()) :: {:ok, [map()]} | {:error, term()}
  def load_entries(entries, import_offset_ms) when is_list(entries) do
    Enum.reduce_while(entries, {:ok, []}, fn entry, {:ok, acc} ->
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

          {:cont, {:ok, [%{player_id: player_id, metadata: metadata, entry: entry} | acc]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, played} -> {:ok, Enum.reverse(played)}
      {:error, _reason} = error -> error
    end
  end

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)
    |> Enum.map(fn {field, messages} -> "#{field} #{Enum.join(messages, ", ")}" end)
    |> Enum.join("; ")
  end
end
