defmodule FirehoseSimulator.SimulationPlan do
  @moduledoc false

  alias FirehoseSimulator.SimulationPlan.Follows
  alias FirehoseSimulator.SimulationPlan.Params.FollowsParams
  alias FirehoseSimulator.SimulationPlan.Posts
  alias FirehoseSimulator.SimulationPlan.Params.PostsParams
  alias FirehoseSimulator.SimulationPlan.Sessions
  alias FirehoseSimulator.SimulationPlan.Params.SessionsParams

  @enforce_keys [:posts_plan, :sessions_plan, :follows_plan]
  defstruct [:posts_plan, :sessions_plan, :follows_plan]

  @type t :: %__MODULE__{
          posts_plan: Posts.t() | nil,
          sessions_plan: Sessions.t() | nil,
          follows_plan: Follows.t() | nil
        }

  @spec load_from_json(keyword(String.t())) :: {:ok, t()} | {:error, String.t()}
  def load_from_json(opts) when is_list(opts) do
    posts_path = Keyword.get(opts, :posts)
    sessions_path = Keyword.get(opts, :sessions)
    follows_path = Keyword.get(opts, :follows)

    with {:ok, posts_plan} <- load_posts_plan(posts_path),
         {:ok, sessions_plan} <- load_sessions_plan(sessions_path),
         {:ok, follows_plan} <- load_follows_plan(follows_path) do
      {:ok,
       %__MODULE__{
         posts_plan: posts_plan,
         sessions_plan: sessions_plan,
         follows_plan: follows_plan
       }}
    end
  end

  defp load_posts_plan(nil), do: {:ok, nil}

  defp load_posts_plan(path) when is_binary(path) do
    case PostsParams.load_file(path) do
      {:ok, posts_params} -> {:ok, Posts.generate(posts_params)}
      {:error, _reason} = error -> error
    end
  end

  defp load_posts_plan(_path), do: {:error, "posts path must be a string"}

  defp load_sessions_plan(nil), do: {:ok, nil}

  defp load_sessions_plan(path) when is_binary(path) do
    case SessionsParams.load_file(path) do
      {:ok, sessions_params} -> {:ok, Sessions.generate(sessions_params)}
      {:error, _reason} = error -> error
    end
  end

  defp load_sessions_plan(_path), do: {:error, "sessions path must be a string"}

  defp load_follows_plan(nil), do: {:ok, nil}

  defp load_follows_plan(path) when is_binary(path) do
    case FollowsParams.load_file(path) do
      {:ok, follows_params} -> {:ok, Follows.generate(follows_params)}
      {:error, _reason} = error -> error
    end
  end

  defp load_follows_plan(_path), do: {:error, "follows path must be a string"}
end
