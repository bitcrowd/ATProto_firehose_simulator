defmodule FirehoseSimulator.Scenario.JSON do
  @moduledoc false

  alias FirehoseSimulator.Scenario

  @default_request_interval_ms 30_000
  @default_timeline_limit 20

  @spec encode(Scenario.t()) :: {:ok, String.t()} | {:error, String.t()}
  def encode(%Scenario{} = scenario) do
    payload = %{
      posts: scenario.posts,
      sessions: scenario.sessions,
      follows: scenario.follows,
      request_interval_ms: scenario.request_interval_ms,
      timeline_limit: scenario.timeline_limit
    }

    case Jason.encode(payload) do
      {:ok, json} -> {:ok, json}
      {:error, reason} -> {:error, "failed to encode scenario json: #{inspect(reason)}"}
    end
  end

  @spec decode(String.t()) :: {:ok, Scenario.t()} | {:error, String.t()}
  def decode(json) when is_binary(json) do
    with {:ok, attrs} <- decode_object(json),
         {:ok, posts} <- decode_posts(Map.get(attrs, "posts")),
         {:ok, sessions} <- decode_sessions(Map.get(attrs, "sessions")),
         {:ok, follows} <- decode_follows(Map.get(attrs, "follows")),
         {:ok, request_interval_ms} <- decode_request_interval_ms(attrs),
         {:ok, timeline_limit} <- decode_timeline_limit(attrs),
         {:ok, scenario} <-
           Scenario.new(%{
             posts: posts,
             sessions: sessions,
             follows: follows,
             request_interval_ms: request_interval_ms,
             timeline_limit: timeline_limit
           }) do
      {:ok, scenario}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, "invalid scenario json: #{format_changeset_errors(changeset)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp decode_object(json) do
    case Jason.decode(json) do
      {:ok, %{} = attrs} -> {:ok, attrs}
      {:ok, _other} -> {:error, "invalid scenario json: expected json object"}
      {:error, _reason} -> {:error, "invalid scenario json"}
    end
  end

  defp decode_posts(nil), do: {:ok, nil}
  defp decode_posts(rows), do: decode_rows(rows, "posts", &decode_post/1)

  defp decode_sessions(nil), do: {:ok, nil}
  defp decode_sessions(rows), do: decode_rows(rows, "sessions", &decode_session/1)

  defp decode_follows(nil), do: {:ok, nil}
  defp decode_follows(rows), do: decode_rows(rows, "follows", &decode_follow/1)

  defp decode_request_interval_ms(attrs) when is_map(attrs) do
    case Map.get(attrs, "request_interval_ms") do
      nil ->
        {:ok, @default_request_interval_ms}

      value when is_integer(value) and value > 0 ->
        {:ok, value}

      _invalid ->
        {:error, "invalid request_interval_ms: must be a positive integer"}
    end
  end

  defp decode_timeline_limit(attrs) when is_map(attrs) do
    case Map.get(attrs, "timeline_limit") do
      nil ->
        {:ok, @default_timeline_limit}

      value when is_integer(value) and value > 0 ->
        {:ok, value}

      _invalid ->
        {:error, "invalid timeline_limit: must be a positive integer"}
    end
  end

  defp decode_rows(rows, label, decoder) when is_list(rows) do
    rows
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {row, index}, {:ok, acc} ->
      case row |> normalize_row_keys() |> decoder.() do
        {:ok, parsed} -> {:cont, {:ok, [parsed | acc]}}
        {:error, reason} -> {:halt, {:error, "invalid #{label}[#{index}]: #{reason}"}}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      {:error, _reason} = error -> error
    end
  end

  defp decode_rows(_rows, label, _decoder),
    do: {:error, "invalid #{label}: expected list or null"}

  defp normalize_row_keys(%{} = row) do
    Map.new(row, fn
      {"offset_ms", value} -> {:offset_ms, value}
      {"user_id", value} -> {:user_id, value}
      {"duration_ms", value} -> {:duration_ms, value}
      {"actor_id", value} -> {:actor_id, value}
      {"subject_id", value} -> {:subject_id, value}
      {key, value} -> {key, value}
    end)
  end

  defp normalize_row_keys(row), do: row

  defp decode_post(%{} = row) do
    with {:ok, offset_ms} <- fetch_integer(row, :offset_ms),
         {:ok, user_id} <- fetch_integer(row, :user_id) do
      {:ok, %{offset_ms: offset_ms, user_id: user_id}}
    end
  end

  defp decode_post(_row), do: {:error, "expected object"}

  defp decode_session(%{} = row) do
    with {:ok, offset_ms} <- fetch_integer(row, :offset_ms),
         {:ok, user_id} <- fetch_integer(row, :user_id),
         {:ok, duration_ms} <- fetch_integer(row, :duration_ms) do
      {:ok, %{offset_ms: offset_ms, user_id: user_id, duration_ms: duration_ms}}
    end
  end

  defp decode_session(_row), do: {:error, "expected object"}

  defp decode_follow(%{} = row) do
    with {:ok, offset_ms} <- fetch_integer(row, :offset_ms),
         {:ok, actor_id} <- fetch_integer(row, :actor_id),
         {:ok, subject_id} <- fetch_integer(row, :subject_id) do
      {:ok, %{offset_ms: offset_ms, actor_id: actor_id, subject_id: subject_id}}
    end
  end

  defp decode_follow(_row), do: {:error, "expected object"}

  defp fetch_integer(map, key) do
    value = Map.get(map, key)

    if is_integer(value) do
      {:ok, value}
    else
      {:error, "#{Atom.to_string(key)} must be an integer"}
    end
  end

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map(fn {field, messages} -> "#{field} #{Enum.join(messages, ", ")}" end)
    |> Enum.join("; ")
  end
end
