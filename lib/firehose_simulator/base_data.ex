defmodule FirehoseSimulator.BaseData do
  @moduledoc """
  Context for base simulation data.

  This area owns userbase validation/loading and deterministic follower graph
  generation used by simulation-plan and bulk-creation workflows.
  """

  alias FirehoseSimulator.BaseData.FollowerGraph
  alias FirehoseSimulator.BaseData.Userbase

  @spec load_userbase(String.t()) :: {:ok, Userbase.t()} | {:error, String.t()}
  def load_userbase(json) when is_binary(json) do
    Userbase.load(json)
  end

  @spec load_userbase_file(String.t()) :: {:ok, Userbase.t()} | {:error, String.t()}
  def load_userbase_file(path) when is_binary(path) do
    Userbase.load_file(path)
  end

  @spec generate_follower_graph(pos_integer(), keyword()) ::
          {:ok, %{optional(pos_integer()) => [pos_integer()]}, non_neg_integer()}
  def generate_follower_graph(num_users, opts \\ [])
      when is_integer(num_users) and num_users > 0 do
    FollowerGraph.generate(num_users, opts)
  end
end
