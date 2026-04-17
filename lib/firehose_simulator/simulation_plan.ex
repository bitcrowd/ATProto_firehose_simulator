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
    |> put_entries(attrs)
  end

  @spec new(map()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def new(attrs \\ %{}) when is_map(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> apply_action(:insert)
  end

  @spec update(t(), map()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def update(%__MODULE__{} = simulation_plan, attrs) when is_map(attrs) do
    simulation_plan
    |> changeset(attrs)
    |> apply_action(:update)
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
           }),
         {:ok, updated_plan} <-
           update(simulation_plan, %{
             name: simulation_plan.name,
             started_at: simulation_plan.started_at,
             export_path: simulation_plan.export_path,
             entries: simulation_plan.entries ++ [entry]
           }) do
      {:ok, updated_plan, entry}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, format_changeset_errors(changeset)}
    end
  end

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)
    |> Enum.map(fn {field, messages} -> "#{field} #{Enum.join(messages, ", ")}" end)
    |> Enum.join("; ")
  end

  defp put_entries(changeset, attrs) do
    case entries_attr(attrs) do
      nil ->
        changeset

      entries when is_list(entries) ->
        if Enum.all?(entries, &match?(%Entry{}, &1)) do
          put_embed(changeset, :entries, entries)
        else
          cast_embed(changeset, :entries, with: &Entry.changeset/2)
        end
    end
  end

  defp entries_attr(attrs) when is_map(attrs) do
    Map.get(attrs, :entries) || Map.get(attrs, "entries")
  end
end
