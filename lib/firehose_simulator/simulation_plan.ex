defmodule FirehoseSimulator.SimulationPlan do
  @moduledoc false

  alias FirehoseSimulator.SimulationPlan.Follows
  alias FirehoseSimulator.SimulationPlan.Posts
  alias FirehoseSimulator.SimulationPlan.Sessions
  alias FirehoseSimulator.SimulationPlan.Params.SimulationPlanParams

  @enforce_keys [:posts, :sessions, :follows]
  defstruct [:posts, :sessions, :follows]

  @type t :: %__MODULE__{
          posts: Posts.t() | nil,
          sessions: Sessions.t() | nil,
          follows: Follows.t() | nil
        }

  @spec load_from_json(String.t()) :: {:ok, t()} | {:error, String.t()}
  def load_from_json(path) when is_binary(path) do
    load_from_json(simulation_plan_params: path)
  end

  @spec load_from_json(keyword(String.t())) :: {:ok, t()} | {:error, String.t()}
  def load_from_json(opts) when is_list(opts) do
    params_path =
      Keyword.get(opts, :simulation_plan_params) || Keyword.get(opts, :params)

    with {:ok, params} <- load_simulation_plan_params(params_path),
         {:ok, posts} <- build_posts(params),
         {:ok, sessions} <- build_sessions(params),
         {:ok, follows} <- build_follows(params) do
      {:ok,
       %__MODULE__{
         posts: posts,
         sessions: sessions,
         follows: follows
       }}
    end
  end

  defp load_simulation_plan_params(nil), do: {:ok, %SimulationPlanParams{}}

  defp load_simulation_plan_params(path) when is_binary(path) do
    case SimulationPlanParams.load_file(path) do
      {:ok, params} -> {:ok, params}
      {:error, _reason} = error -> error
    end
  end

  defp load_simulation_plan_params(_path),
    do: {:error, "simulation_plan_params path must be a string"}

  defp build_posts(%SimulationPlanParams{posts_params: nil}), do: {:ok, nil}

  defp build_posts(%SimulationPlanParams{posts_params: posts_params}) do
    {:ok, Posts.generate(posts_params)}
  end

  defp build_sessions(%SimulationPlanParams{sessions_params: nil}), do: {:ok, nil}

  defp build_sessions(%SimulationPlanParams{sessions_params: sessions_params}) do
    {:ok, Sessions.generate(sessions_params)}
  end

  defp build_follows(%SimulationPlanParams{follows_params: nil}), do: {:ok, nil}

  defp build_follows(%SimulationPlanParams{follows_params: follows_params}) do
    {:ok, Follows.generate(follows_params)}
  end
end
