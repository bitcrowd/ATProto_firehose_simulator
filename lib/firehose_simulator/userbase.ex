defmodule FirehoseSimulator.Userbase do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

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
    field(:follower_density, :float)
  end

  @spec load(String.t()) :: {:ok, t()} | {:error, String.t()}
  def load(path) when is_binary(path) do
    with {:ok, json} <- read_json_file(path),
         {:ok, attrs} <- decode_json(path, json),
         {:ok, userbase} <- validate(path, attrs) do
      {:ok, userbase}
    end
  end

  @spec load!(String.t()) :: t()
  def load!(path) when is_binary(path) do
    case load(path) do
      {:ok, userbase} -> userbase
      {:error, message} -> raise RuntimeError, message
    end
  end

  defp read_json_file(path) do
    case File.read(path) do
      {:ok, json} -> {:ok, json}
      {:error, _reason} -> {:error, "cannot read userbase file at #{path}"}
    end
  end

  defp decode_json(path, json) do
    case Jason.decode(json) do
      {:ok, %{} = attrs} -> {:ok, attrs}
      {:ok, _not_an_object} -> {:error, "invalid userbase json at #{path}: expected json object"}
      {:error, _reason} -> {:error, "invalid userbase json at #{path}"}
    end
  end

  defp validate(path, attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> apply_action(:validate)
    |> case do
      {:ok, validated} ->
        {:ok, validated}

      {:error, changeset} ->
        {:error, "invalid userbase config at #{path}: #{format_changeset_errors(changeset)}"}
    end
  end

  defp format_changeset_errors(changeset) do
    changeset
    |> traverse_errors(fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map(fn {field, messages} ->
      "#{field}: #{Enum.join(messages, ", ")}"
    end)
    |> Enum.join("; ")
  end

  defp changeset(userbase, attrs) do
    userbase
    |> cast(attrs, [:name, :num_users, :max_active_user_id, :follower_density])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name, :num_users, :max_active_user_id, :follower_density])
    |> validate_length(:name, min: 1)
    |> validate_number(:num_users, greater_than: 0)
    |> validate_number(:max_active_user_id, greater_than: 0)
    |> validate_number(:follower_density, greater_than_or_equal_to: 0)
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
