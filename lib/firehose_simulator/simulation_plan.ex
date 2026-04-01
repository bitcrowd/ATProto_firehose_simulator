defmodule FirehoseSimulator.SimulationPlan do
  @moduledoc false

  alias FirehoseSimulator.SimulationPlan.Follows
  alias FirehoseSimulator.SimulationPlan.FollowsParams
  alias FirehoseSimulator.SimulationPlan.Posts
  alias FirehoseSimulator.SimulationPlan.PostsParams
  alias FirehoseSimulator.SimulationPlan.Sessions
  alias FirehoseSimulator.SimulationPlan.SessionsParams

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

  defp apply_shift(%__MODULE__{} = plan, 0), do: plan

  defp apply_shift(%__MODULE__{} = plan, shift) do
    %__MODULE__{
      sessions_plan: shift_sessions(plan.sessions_plan, shift),
      posts_plan: shift_posts(plan.posts_plan, shift),
      follows_plan: shift_follows(plan.follows_plan, shift)
    }
  end

  defp shift_sessions(nil, _shift), do: nil

  defp shift_sessions(%Sessions{sessions: sessions} = sessions_plan, shift) do
    shifted =
      Enum.map(sessions, fn session ->
        %{session | offset_ms: session.offset_ms + shift}
      end)

    %{sessions_plan | sessions: shifted}
  end

  defp shift_posts(nil, _shift), do: nil

  defp shift_posts(%Posts{posts: posts} = posts_plan, shift) do
    shifted =
      Enum.map(posts, fn post ->
        %{post | offset_ms: post.offset_ms + shift}
      end)

    %{posts_plan | posts: shifted}
  end

  defp shift_follows(nil, _shift), do: nil

  defp shift_follows(%Follows{follows: follows} = follows_plan, shift) do
    shifted =
      Enum.map(follows, fn follow ->
        %{follow | offset_ms: follow.offset_ms + shift}
      end)

    %{follows_plan | follows: shifted}
  end

  defp sessions_offsets(nil), do: []
  defp sessions_offsets(%Sessions{sessions: sessions}), do: Enum.map(sessions, & &1.offset_ms)

  defp posts_offsets(nil), do: []
  defp posts_offsets(%Posts{posts: posts}), do: Enum.map(posts, & &1.offset_ms)

  defp follows_offsets(nil), do: []
  defp follows_offsets(%Follows{follows: follows}), do: Enum.map(follows, & &1.offset_ms)
end
