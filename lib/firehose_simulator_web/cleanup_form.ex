defmodule FirehoseSimulatorWeb.CleanupForm do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field(:database_url, :string)
  end

  def form(params \\ %{}) do
    params
    |> stringify_keys()
    |> changeset()
    |> Map.put(:action, nil)
    |> to_form()
  end

  def validate(params) do
    params
    |> stringify_keys()
    |> changeset()
    |> Map.put(:action, :validate)
    |> case do
      changeset when changeset.valid? -> {:ok, get_field(changeset, :database_url)}
      changeset -> {:error, changeset}
    end
  end

  def from_changeset(changeset) do
    changeset
    |> to_form()
  end

  defp to_form(changeset) do
    params =
      case changeset.params do
        nil -> %{}
        params -> params
      end

    Phoenix.Component.to_form(params,
      as: :cleanup,
      errors: changeset.errors,
      action: changeset.action
    )
  end

  defp changeset(params) do
    %__MODULE__{}
    |> cast(params, [:database_url])
    |> update_change(:database_url, &String.trim/1)
    |> validate_required([:database_url], message: "Database URL is required")
    |> validate_format(:database_url, ~r/^postgres(ql)?:\/\//,
      message: "Database URL must be postgres:// or postgresql://"
    )
  end

  defp stringify_keys(params) do
    Map.new(params, fn {key, value} -> {to_string(key), value} end)
  end
end
