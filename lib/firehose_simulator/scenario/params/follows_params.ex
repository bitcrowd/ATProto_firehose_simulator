defmodule FirehoseSimulator.Scenario.Params.FollowsParams do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset
  alias FirehoseSimulator.Scenario.JsonEmbeddedLoader
  alias FirehoseSimulator.Scenario.Params.FollowTier

  @type t :: %__MODULE__{
          num_users: pos_integer(),
          max_active_user_id: pos_integer(),
          follower_density: float(),
          tiers: [FollowTier.t()]
        }

  @primary_key false
  embedded_schema do
    field(:num_users, :integer)
    field(:max_active_user_id, :integer)
    field(:follower_density, :float, default: 1.0)
    embeds_many(:tiers, FollowTier, on_replace: :delete)
  end

  @spec load(String.t()) :: {:ok, t()} | {:error, String.t()}
  def load(json) when is_binary(json) do
    JsonEmbeddedLoader.load(json, "follows", %__MODULE__{}, &changeset/2)
  end

  @spec load!(String.t()) :: t()
  def load!(json) when is_binary(json) do
    JsonEmbeddedLoader.load!(json, "follows", %__MODULE__{}, &changeset/2)
  end

  @spec load_file(String.t()) :: {:ok, t()} | {:error, String.t()}
  def load_file(path) when is_binary(path) do
    case File.read(path) do
      {:ok, json} -> load(json)
      {:error, _reason} -> {:error, "cannot read follows file at #{path}"}
    end
  end

  @spec load_file!(String.t()) :: t()
  def load_file!(path) when is_binary(path) do
    case load_file(path) do
      {:ok, follows} -> follows
      {:error, message} -> raise RuntimeError, message
    end
  end

  def changeset(follows, attrs) do
    follows
    |> cast(attrs, [:num_users, :max_active_user_id, :follower_density])
    |> validate_required([:num_users, :max_active_user_id])
    |> validate_number(:num_users, greater_than: 0)
    |> validate_number(:max_active_user_id, greater_than: 0)
    |> validate_number(:follower_density, greater_than: 0)
    |> cast_embed(:tiers, required: true, with: &FollowTier.changeset/2)
    |> validate_length(:tiers, min: 1)
    |> update_change(
      :tiers,
      &Enum.sort_by(&1, fn t -> Ecto.Changeset.get_field(t, :max_followers) end)
    )
  end
end
