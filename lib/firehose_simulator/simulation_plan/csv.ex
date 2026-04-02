defmodule FirehoseSimulator.SimulationPlan.CSV do
  @moduledoc """
  Shared CSV helpers for simulation plan modules.
  """

  alias FirehoseSimulator.SimulationPlan

  @spec write(SimulationPlan.t(), keyword(String.t())) :: :ok | {:error, String.t()}
  def write(%SimulationPlan{} = simulation_plan, paths) when is_list(paths) do
    with :ok <- validate_paths(paths),
         :ok <- ensure_has_paths(paths) do
      Enum.reduce_while(paths, :ok, fn
        {:posts, path}, :ok ->
          write_section(simulation_plan.posts, path, :posts)

        {:sessions, path}, :ok ->
          write_section(simulation_plan.sessions, path, :sessions)

        {:follows, path}, :ok ->
          write_section(simulation_plan.follows, path, :follows)

        {key, _path}, :ok ->
          {:halt, {:error, "unknown simulation plan csv key: #{inspect(key)}"}}
      end)
    end
  end

  def write(_simulation_plan, _paths), do: {:error, "invalid simulation plan or csv paths"}

  @spec load(:posts | :sessions | :follows, String.t()) ::
          {:ok, [map()]} | {:error, String.t()}
  def load(:posts, path) when is_binary(path) do
    with {:ok, csv} <- File.read(path) do
      parse_posts(csv)
    else
      {:error, :enoent} -> {:error, "cannot read posts csv at #{path}"}
      {:error, _reason} = error -> error
    end
  end

  def load(:sessions, path) when is_binary(path) do
    with {:ok, csv} <- File.read(path) do
      parse_sessions(csv)
    else
      {:error, :enoent} -> {:error, "cannot read sessions csv at #{path}"}
      {:error, _reason} = error -> error
    end
  end

  def load(:follows, path) when is_binary(path) do
    with {:ok, csv} <- File.read(path) do
      parse_follows(csv)
    else
      {:error, :enoent} -> {:error, "cannot read follows csv at #{path}"}
      {:error, _reason} = error -> error
    end
  end

  defp validate_paths(paths) do
    if Enum.all?(paths, fn {_key, path} -> is_binary(path) end) do
      :ok
    else
      {:error, "all csv paths must be strings"}
    end
  end

  defp ensure_has_paths([]), do: {:error, "at least one csv path must be provided"}
  defp ensure_has_paths(_paths), do: :ok

  defp write_section(nil, _path, section), do: {:halt, {:error, "#{section} list is nil"}}

  defp write_section(rows, path, :posts) when is_list(rows) do
    case write_rows(rows, "offset_ms,user_id", &"#{&1.offset_ms},#{&1.user_id}", path) do
      :ok -> {:cont, :ok}
      {:error, reason} -> {:halt, {:error, "failed to write posts csv: #{inspect(reason)}"}}
    end
  end

  defp write_section(rows, path, :sessions) when is_list(rows) do
    case write_rows(
           rows,
           "offset_ms,user_id,duration_ms",
           &"#{&1.offset_ms},#{&1.user_id},#{&1.duration_ms}",
           path
         ) do
      :ok -> {:cont, :ok}
      {:error, reason} -> {:halt, {:error, "failed to write sessions csv: #{inspect(reason)}"}}
    end
  end

  defp write_section(rows, path, :follows) when is_list(rows) do
    case write_rows(
           rows,
           "offset_ms,actor_id,subject_id",
           &"#{&1.offset_ms},#{&1.actor_id},#{&1.subject_id}",
           path
         ) do
      :ok -> {:cont, :ok}
      {:error, reason} -> {:halt, {:error, "failed to write follows csv: #{inspect(reason)}"}}
    end
  end

  defp write_section(_rows, _path, section),
    do: {:halt, {:error, "invalid #{section} list in simulation plan"}}

  defp write_rows(rows, header, row_formatter, path) do
    body =
      rows
      |> Enum.map(row_formatter)
      |> Enum.join("\n")

    contents =
      case body do
        "" -> header <> "\n"
        _body -> header <> "\n" <> body <> "\n"
      end

    File.write(path, contents)
  end

  defp parse_posts(csv) do
    case String.split(csv, "\n", trim: true) do
      ["offset_ms,user_id" | rows] ->
        Enum.reduce_while(rows, {:ok, []}, fn row, {:ok, acc} ->
          case String.split(row, ",", parts: 2) do
            [offset_ms, user_id] ->
              with {offset_ms, ""} <- Integer.parse(offset_ms),
                   {user_id, ""} <- Integer.parse(user_id) do
                {:cont, {:ok, acc ++ [%{offset_ms: offset_ms, user_id: user_id}]}}
              else
                _ -> {:halt, {:error, "invalid posts csv"}}
              end

            _ ->
              {:halt, {:error, "invalid posts csv"}}
          end
        end)

      _ ->
        {:error, "invalid posts csv"}
    end
  end

  defp parse_sessions(csv) do
    case String.split(csv, "\n", trim: true) do
      ["offset_ms,user_id,duration_ms" | rows] ->
        Enum.reduce_while(rows, {:ok, []}, fn row, {:ok, acc} ->
          case String.split(row, ",", parts: 3) do
            [offset_ms, user_id, duration_ms] ->
              with {offset_ms, ""} <- Integer.parse(offset_ms),
                   {user_id, ""} <- Integer.parse(user_id),
                   {duration_ms, ""} <- Integer.parse(duration_ms) do
                {:cont,
                 {:ok,
                  acc ++ [%{offset_ms: offset_ms, user_id: user_id, duration_ms: duration_ms}]}}
              else
                _ -> {:halt, {:error, "invalid sessions csv"}}
              end

            _ ->
              {:halt, {:error, "invalid sessions csv"}}
          end
        end)

      _ ->
        {:error, "invalid sessions csv"}
    end
  end

  defp parse_follows(csv) do
    case String.split(csv, "\n", trim: true) do
      ["offset_ms,actor_id,subject_id" | rows] ->
        Enum.reduce_while(rows, {:ok, []}, fn row, {:ok, acc} ->
          case String.split(row, ",", parts: 3) do
            [offset_ms, actor_id, subject_id] ->
              with {offset_ms, ""} <- Integer.parse(offset_ms),
                   {actor_id, ""} <- Integer.parse(actor_id),
                   {subject_id, ""} <- Integer.parse(subject_id) do
                {:cont,
                 {:ok,
                  acc ++ [%{offset_ms: offset_ms, actor_id: actor_id, subject_id: subject_id}]}}
              else
                _ -> {:halt, {:error, "invalid follows csv"}}
              end

            _ ->
              {:halt, {:error, "invalid follows csv"}}
          end
        end)

      _ ->
        {:error, "invalid follows csv"}
    end
  end
end
