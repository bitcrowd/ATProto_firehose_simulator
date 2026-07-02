defmodule FirehoseSimulator.Scenario.Params.SessionsParams do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias FirehoseSimulator.Scenario.JsonEmbeddedLoader
  alias FirehoseSimulator.Scenario.Params.SessionTier

  @type t :: %__MODULE__{
          num_users: pos_integer(),
          max_active_user_id: pos_integer(),
          follower_density: float(),
          request_interval_ms: pos_integer(),
          timeline_limit: pos_integer(),
          tiers: [SessionTier.t()]
        }

  @default_request_interval_ms 30_000
  @default_timeline_limit 20

  def default_request_interval_ms, do: @default_request_interval_ms
  def default_timeline_limit, do: @default_timeline_limit

  @primary_key false
  embedded_schema do
    field(:num_users, :integer)
    field(:max_active_user_id, :integer)
    field(:follower_density, :float, default: 1.0)
    field(:request_interval_ms, :integer, default: @default_request_interval_ms)
    field(:timeline_limit, :integer, default: @default_timeline_limit)
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
      :request_interval_ms,
      :timeline_limit
    ])
    |> validate_required([:num_users, :max_active_user_id])
    |> validate_number(:num_users, greater_than: 0)
    |> validate_number(:max_active_user_id, greater_than: 0)
    |> validate_number(:follower_density, greater_than: 0)
    |> validate_number(:request_interval_ms, greater_than: 0)
    |> validate_number(:timeline_limit, greater_than: 0)
    |> cast_embed(:tiers, required: true, with: &SessionTier.changeset/2)
    |> validate_length(:tiers, min: 1)
    |> update_change(:tiers, &Enum.sort_by(&1, fn t -> t.max_followers end))
  end
end
