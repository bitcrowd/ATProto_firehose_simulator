defmodule FirehoseSimulator.SimulationPlan do
  @moduledoc false

  alias FirehoseSimulator.SimulationPlan.Follows
  alias FirehoseSimulator.SimulationPlan.Posts
  alias FirehoseSimulator.SimulationPlan.Sessions

  @enforce_keys [:posts, :sessions, :follows]
  defstruct [:posts, :sessions, :follows]

  @type t :: %__MODULE__{
          posts: Posts.t() | nil,
          sessions: Sessions.t() | nil,
          follows: Follows.t() | nil
        }

  @spec load_from_json(keyword(String.t())) :: {:ok, t()} | {:error, String.t()}
  def load_from_json(opts) when is_list(opts) do
    posts_path = Keyword.get(opts, :posts)
    sessions_path = Keyword.get(opts, :sessions)
    follows_path = Keyword.get(opts, :follows)

    with {:ok, posts} <- load_posts(posts_path),
         {:ok, sessions} <- load_sessions(sessions_path),
         {:ok, follows} <- load_follows(follows_path) do
      {:ok, %__MODULE__{posts: posts, sessions: sessions, follows: follows}}
    end
  end

  defp load_posts(nil), do: {:ok, nil}
  defp load_posts(path) when is_binary(path), do: Posts.load_file(path)
  defp load_posts(_path), do: {:error, "posts path must be a string"}

  defp load_sessions(nil), do: {:ok, nil}
  defp load_sessions(path) when is_binary(path), do: Sessions.load_file(path)
  defp load_sessions(_path), do: {:error, "sessions path must be a string"}

  defp load_follows(nil), do: {:ok, nil}
  defp load_follows(path) when is_binary(path), do: Follows.load_file(path)
  defp load_follows(_path), do: {:error, "follows path must be a string"}
end
