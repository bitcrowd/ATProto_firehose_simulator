defmodule FirehoseSimulator.BaseData.Userbase do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias FirehoseSimulator.SimulationPlan.JsonEmbeddedLoader

  @type t :: %__MODULE__{
          name: String.t(),
          num_users: pos_integer(),
          max_active_user_id: pos_integer(),
          follower_density: float()
        }

  @primary_key false
  embedded_schema do
    field(:name, :string)
    field(:num_users, :integer)
    field(:max_active_user_id, :integer)
    field(:follower_density, :float, default: 1.0)
  end

  @spec load(String.t()) :: {:ok, t()} | {:error, String.t()}
  def load(json) when is_binary(json) do
    JsonEmbeddedLoader.load(json, "userbase", %__MODULE__{}, &changeset/2)
  end

  @spec load!(String.t()) :: t()
  def load!(json) when is_binary(json) do
    JsonEmbeddedLoader.load!(json, "userbase", %__MODULE__{}, &changeset/2)
  end

  @spec load_file(String.t()) :: {:ok, t()} | {:error, String.t()}
  def load_file(path) when is_binary(path) do
    case File.read(path) do
      {:ok, json} -> load(json)
      {:error, _reason} -> {:error, "cannot read userbase file at #{path}"}
    end
  end

  @spec load_file!(String.t()) :: t()
  def load_file!(path) when is_binary(path) do
    case load_file(path) do
      {:ok, userbase} -> userbase
      {:error, message} -> raise RuntimeError, message
    end
  end

  def changeset(userbase, attrs) do
    userbase
    |> cast(attrs, [:name, :num_users, :max_active_user_id, :follower_density])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name, :num_users, :max_active_user_id])
    |> validate_length(:name, min: 1)
    |> validate_number(:num_users, greater_than: 0)
    |> validate_number(:max_active_user_id, greater_than: 0)
    |> validate_number(:follower_density, greater_than: 0)
    |> validate_max_active_user_id_within_num_users()
  end

  defp validate_max_active_user_id_within_num_users(changeset) do
    num_users = get_field(changeset, :num_users)
    max_active_user_id = get_field(changeset, :max_active_user_id)

    if is_integer(num_users) and is_integer(max_active_user_id) and max_active_user_id > num_users do
      add_error(changeset, :max_active_user_id, "must be less than or equal to num_users")
    else
      changeset
    end
  end
end
