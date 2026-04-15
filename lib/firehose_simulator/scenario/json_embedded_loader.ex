defmodule FirehoseSimulator.Scenario.JsonEmbeddedLoader do
  @moduledoc false

  import Ecto.Changeset, only: [apply_action: 2, traverse_errors: 2]

  @spec load(String.t(), String.t(), struct(), (struct(), map() -> Ecto.Changeset.t())) ::
          {:ok, struct()} | {:error, String.t()}
  def load(json, label, struct, changeset_fun) when is_binary(json) and is_binary(label) do
    with {:ok, attrs} <- decode_json(json, label),
         {:ok, validated} <- validate(label, struct, attrs, changeset_fun) do
      {:ok, validated}
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
    |> apply_action(:validate)
    |> case do
      {:ok, validated} ->
        {:ok, validated}

      {:error, changeset} ->
        {:error, "invalid #{label} config: #{format_changeset_errors(changeset)}"}
    end
  end

  defp format_changeset_errors(changeset) do
    changeset
    |> traverse_errors(fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> format_error_entries()
    |> Enum.join("; ")
  end

  defp format_error_entries(errors) when is_map(errors) do
    Enum.flat_map(errors, fn {field, value} ->
      format_error_value(to_string(field), value)
    end)
  end

  defp format_error_value(field, messages) when is_list(messages) do
    if Enum.all?(messages, &is_binary/1) do
      ["#{field}: #{Enum.join(messages, ", ")}"]
    else
      Enum.with_index(messages)
      |> Enum.flat_map(fn {value, index} ->
        format_error_value("#{field}[#{index}]", value)
      end)
    end
  end

  defp format_error_value(field, value) when is_map(value) do
    value
    |> format_error_entries()
    |> Enum.map(fn message -> "#{field}.#{message}" end)
  end
end
