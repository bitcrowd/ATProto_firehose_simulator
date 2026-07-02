defmodule FirehoseSimulator.Changeset do
  @moduledoc false

  @doc """
  Flattens changeset errors into a single human-readable string.
  """
  @spec format_errors(Ecto.Changeset.t()) :: String.t()
  def format_errors(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
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
