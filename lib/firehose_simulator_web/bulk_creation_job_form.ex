defmodule FirehoseSimulatorWeb.BulkCreationJobForm do
  use Ecto.Schema

  import Ecto.Changeset
  import Phoenix.Component, only: [to_form: 2]

  @primary_key false
  embedded_schema do
    field(:count, :integer, default: 100)
  end

  def form(name, params \\ %{}) when name in [:follows_job, :posts_job] do
    to_form(normalize_params(params), as: name)
  end

  def form_from_changeset(name, changeset) when name in [:follows_job, :posts_job] do
    to_form(
      %{"count" => Ecto.Changeset.get_field(changeset, :count)},
      as: name,
      errors: changeset.errors
    )
  end

  def validate(params) do
    changeset = changeset(%__MODULE__{}, params)

    case apply_action(changeset, :validate) do
      {:ok, job} -> {:ok, job}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp changeset(form, attrs) do
    form
    |> cast(attrs, [:count])
    |> validate_required([:count], message: "Count is required")
    |> validate_number(:count, greater_than: 0, message: "Count must be greater than 0")
  end

  defp normalize_params(%{"count" => _value} = params), do: params
  defp normalize_params(%{count: value}), do: %{"count" => value}
  defp normalize_params(_params), do: %{"count" => 100}
end
