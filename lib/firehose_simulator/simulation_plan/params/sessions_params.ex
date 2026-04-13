defmodule FirehoseSimulator.SimulationPlan.Params.SessionsParams do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias FirehoseSimulator.SimulationPlan.JsonEmbeddedLoader
  alias FirehoseSimulator.SimulationPlan.Params.SessionTier

  @type t :: %__MODULE__{
          num_users: pos_integer(),
          max_active_user_id: pos_integer(),
          follower_density: float(),
          request_interval_ms: pos_integer(),
          tiers: [SessionTier.t()]
        }

  @primary_key false
  embedded_schema do
    field(:num_users, :integer)
    field(:max_active_user_id, :integer)
    field(:follower_density, :float, default: 1.0)
    field(:request_interval_ms, :integer, default: 30_000)
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
    |> cast(attrs, [
      :num_users,
      :max_active_user_id,
      :follower_density,
      :request_interval_ms
    ])
    |> validate_required([:num_users, :max_active_user_id])
    |> validate_number(:num_users, greater_than: 0)
    |> validate_number(:max_active_user_id, greater_than: 0)
    |> validate_number(:follower_density, greater_than: 0)
    |> validate_number(:request_interval_ms, greater_than: 0)
    |> cast_embed(:tiers, required: true, with: &SessionTier.changeset/2)
    |> validate_length(:tiers, min: 1)
  end
end
