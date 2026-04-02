defmodule FirehoseSimulator.SimulationPlan.Params.SimulationPlanParams do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias FirehoseSimulator.SimulationPlan.JsonEmbeddedLoader
  alias FirehoseSimulator.SimulationPlan.Params.FollowsParams
  alias FirehoseSimulator.SimulationPlan.Params.PostsParams
  alias FirehoseSimulator.SimulationPlan.Params.SessionsParams

  @type t :: %__MODULE__{
          posts_params: PostsParams.t() | nil,
          sessions_params: SessionsParams.t() | nil,
          follows_params: FollowsParams.t() | nil
        }

  @primary_key false
  embedded_schema do
    embeds_one(:posts_params, PostsParams, on_replace: :delete)
    embeds_one(:sessions_params, SessionsParams, on_replace: :delete)
    embeds_one(:follows_params, FollowsParams, on_replace: :delete)
  end

  @spec load(String.t()) :: {:ok, t()} | {:error, String.t()}
  def load(json) when is_binary(json) do
    JsonEmbeddedLoader.load(json, "simulation plan params", %__MODULE__{}, &changeset/2)
  end

  @spec load!(String.t()) :: t()
  def load!(json) when is_binary(json) do
    JsonEmbeddedLoader.load!(json, "simulation plan params", %__MODULE__{}, &changeset/2)
  end

  @spec load_file(String.t()) :: {:ok, t()} | {:error, String.t()}
  def load_file(path) when is_binary(path) do
    case File.read(path) do
      {:ok, json} -> load(json)
      {:error, _reason} -> {:error, "cannot read simulation plan params file at #{path}"}
    end
  end

  @spec load_file!(String.t()) :: t()
  def load_file!(path) when is_binary(path) do
    case load_file(path) do
      {:ok, params} -> params
      {:error, message} -> raise RuntimeError, message
    end
  end

  def changeset(params, attrs) do
    params
    |> cast(attrs, [])
    |> cast_embed(:posts_params, with: &PostsParams.changeset/2)
    |> cast_embed(:sessions_params, with: &SessionsParams.changeset/2)
    |> cast_embed(:follows_params, with: &FollowsParams.changeset/2)
  end
end
