defmodule FirehoseSimulator.SimulationPlan.CSV do
  @moduledoc """
  Shared CSV helpers for simulation plan modules.
  """

  alias FirehoseSimulator.SimulationPlan.Follows
  alias FirehoseSimulator.SimulationPlan.Posts
  alias FirehoseSimulator.SimulationPlan.Sessions

  @spec write(Posts.t() | Sessions.t() | Follows.t(), String.t()) ::
          :ok | {:error, term()}
  def write(%Posts{posts: posts}, path) when is_binary(path) do
    write_rows(
      posts,
      "offset_ms,user_id",
      fn post -> "#{post.offset_ms},#{post.user_id}" end,
      path
    )
  end

  def write(%Sessions{sessions: sessions}, path) when is_binary(path) do
    write_rows(
      sessions,
      "offset_ms,user_id,duration_ms",
      fn session -> "#{session.offset_ms},#{session.user_id},#{session.duration_ms}" end,
      path
    )
  end

  def write(%Follows{follows: follows}, path) when is_binary(path) do
    write_rows(
      follows,
      "offset_ms,actor_id,subject_id",
      fn follow -> "#{follow.offset_ms},#{follow.actor_id},#{follow.subject_id}" end,
      path
    )
  end

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
