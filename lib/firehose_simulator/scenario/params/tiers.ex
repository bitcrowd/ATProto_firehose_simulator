defmodule FirehoseSimulator.Scenario.Params.Tiers do
  alias FirehoseSimulator.BaseData.FollowerGraph

  @doc """
  Look up the tier for a user based on their follower count. First match wins.
  """
  def lookup(user_id, num_users, tiers, follower_density \\ 1.0) do
    follower_count = FollowerGraph.follower_count(user_id, num_users, follower_density)
    Enum.find(tiers, List.last(tiers), fn tier -> follower_count <= tier.max_followers end)
  end
end
