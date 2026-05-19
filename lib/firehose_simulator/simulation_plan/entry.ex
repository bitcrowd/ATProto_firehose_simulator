defmodule FirehoseSimulator.SimulationPlan.Entry do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias FirehoseSimulator.Scenario

  @primary_key false
  embedded_schema do
    field(:scenario_name, :string)
    field(:scenario_path, :string)
    field(:offset_ms, :integer)
    field(:scenario, :map, virtual: true)
  end

  @type t :: %__MODULE__{
          scenario_name: String.t() | nil,
          scenario_path: String.t() | nil,
          offset_ms: integer() | nil,
          scenario: Scenario.t() | nil
        }

  @spec changeset(t(), map() | t()) :: Ecto.Changeset.t()
  def changeset(entry, attrs) do
    attrs = normalize_attrs(attrs)

    entry
    |> cast(attrs, [:scenario_name, :scenario_path, :offset_ms])
    |> put_scenario(attrs)
    |> update_change(:scenario_name, &String.trim/1)
    |> update_change(:scenario_path, &String.trim/1)
    |> validate_required([:scenario_name, :scenario_path, :offset_ms])
    |> validate_length(:scenario_name, min: 1)
    |> validate_length(:scenario_path, min: 1)
  end

  @spec new(map()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def new(attrs) when is_map(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> apply_action(:insert)
  end

  @spec update(t(), map()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def update(%__MODULE__{} = entry, attrs) when is_map(attrs) do
    entry
    |> changeset(attrs)
    |> apply_action(:update)
  end

  defp put_scenario(changeset, %{"scenario" => %Scenario{} = scenario}) do
    put_change(changeset, :scenario, scenario)
  end

  defp put_scenario(changeset, %{scenario: %Scenario{} = scenario}) do
    put_change(changeset, :scenario, scenario)
  end

  defp put_scenario(changeset, _attrs), do: changeset

  defp normalize_attrs(%__MODULE__{} = entry), do: Map.from_struct(entry)
  defp normalize_attrs(attrs), do: attrs
end
