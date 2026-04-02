defmodule FirehoseSimulator.SimulationPlan.Params.SessionsParams do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias FirehoseSimulator.SimulationPlan.JsonEmbeddedLoader
  alias FirehoseSimulator.SimulationPlan.Params.SessionTier

  @type t :: %__MODULE__{
          n: pos_integer(),
          max_active_user_id: pos_integer(),
          seed: integer(),
          time_units: pos_integer(),
          path: String.t(),
          tiers: [SessionTier.t()]
        }

  @primary_key false
  embedded_schema do
    field(:n, :integer)
    field(:max_active_user_id, :integer)
    field(:seed, :integer)
    field(:time_units, :integer)
    field(:path, :string)
    embeds_many(:tiers, SessionTier, on_replace: :delete)
  end

  @spec load(String.t()) :: {:ok, t()} | {:error, String.t()}
  def load(json) when is_binary(json) do
    JsonEmbeddedLoader.load(json, "sessions", %__MODULE__{}, &changeset/2)
  end

  @spec load!(String.t()) :: t()
  def load!(json) when is_binary(json) do
    JsonEmbeddedLoader.load!(json, "sessions", %__MODULE__{}, &changeset/2)
  end

  @spec load_file(String.t()) :: {:ok, t()} | {:error, String.t()}
  def load_file(path) when is_binary(path) do
    case File.read(path) do
      {:ok, json} -> load(json)
      {:error, _reason} -> {:error, "cannot read sessions file at #{path}"}
    end
  end

  @spec load_file!(String.t()) :: t()
  def load_file!(path) when is_binary(path) do
    case load_file(path) do
      {:ok, sessions} -> sessions
      {:error, message} -> raise RuntimeError, message
    end
  end

  def changeset(sessions, attrs) do
    sessions
    |> cast(attrs, [:n, :max_active_user_id, :seed, :time_units, :path])
    |> update_change(:path, &String.trim/1)
    |> validate_required([:n, :max_active_user_id, :seed, :time_units, :path])
    |> validate_number(:n, greater_than: 0)
    |> validate_number(:max_active_user_id, greater_than: 0)
    |> validate_number(:time_units, greater_than: 0)
    |> validate_length(:path, min: 1)
    |> cast_embed(:tiers, required: true, with: &SessionTier.changeset/2)
    |> validate_length(:tiers, min: 1)
  end
end
