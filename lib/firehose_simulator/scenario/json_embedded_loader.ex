defmodule FirehoseSimulator.Scenario.JsonEmbeddedLoader do
  @moduledoc false

  alias FirehoseSimulator.Changeset

  @spec load(String.t(), String.t(), struct(), (struct(), map() -> Ecto.Changeset.t())) ::
          {:ok, struct()} | {:error, String.t()}
  def load(json, label, struct, changeset_fun) when is_binary(json) and is_binary(label) do
    with {:ok, attrs} <- decode_json(json, label) do
      validate(label, struct, attrs, changeset_fun)
    end
  end

  @spec load!(String.t(), String.t(), struct(), (struct(), map() -> Ecto.Changeset.t())) ::
          struct()
  def load!(json, label, struct, changeset_fun) when is_binary(json) and is_binary(label) do
    case load(json, label, struct, changeset_fun) do
      {:ok, validated} -> validated
      {:error, message} -> raise RuntimeError, message
    end
  end

  defp decode_json(json, label) do
    case Jason.decode(json) do
      {:ok, %{} = attrs} -> {:ok, attrs}
      {:ok, _not_an_object} -> {:error, "invalid #{label} json: expected json object"}
      {:error, _reason} -> {:error, "invalid #{label} json"}
    end
  end

  defp validate(label, struct, attrs, changeset_fun) do
    struct
    |> changeset_fun.(attrs)
    |> Ecto.Changeset.apply_action(:validate)
    |> case do
      {:ok, validated} ->
        {:ok, validated}

      {:error, changeset} ->
        {:error, "invalid #{label} config: #{Changeset.format_errors(changeset)}"}
    end
  end
end
