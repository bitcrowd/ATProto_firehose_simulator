defmodule FirehoseSimulatorWeb.BulkCreationConnectionForm do
  use Ecto.Schema

  import Ecto.Changeset
  import Phoenix.Component, only: [to_form: 2]

  @primary_key false
  embedded_schema do
    field(:connection_string, :string)
  end

  def form(params \\ %{}) do
    to_form(normalize_params(params), as: :connection)
  end

  def form_from_changeset(changeset) do
    to_form(
      %{"connection_string" => Ecto.Changeset.get_field(changeset, :connection_string)},
      as: :connection,
      errors: changeset.errors
    )
  end

  def validate(params) do
    changeset = changeset(%__MODULE__{}, params)

    case apply_action(changeset, :validate) do
      {:ok, config} -> {:ok, config}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp changeset(form, attrs) do
    form
    |> cast(attrs, [:connection_string])
    |> update_change(:connection_string, &String.trim/1)
    |> validate_required([:connection_string], message: "Connection string is required")
    |> validate_format(:connection_string, ~r/^(postgres|ecto):\/\//,
      message: "Connection string must be a postgres URL"
    )
  end

  defp normalize_params(%{"connection_string" => _value} = params), do: params
  defp normalize_params(%{connection_string: value}), do: %{"connection_string" => value}
  defp normalize_params(_params), do: %{}
end
