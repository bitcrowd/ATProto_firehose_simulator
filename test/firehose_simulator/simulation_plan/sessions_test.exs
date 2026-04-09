defmodule FirehoseSimulator.SimulationPlan.SessionsTest do
  use ExUnit.Case, async: false

  alias FirehoseSimulator.SimulationPlan.Sessions
  alias FirehoseSimulator.SimulationPlan.Params.SessionsParams

  @config %SessionsParams{
    n: 100,
    max_active_user_id: 2,
    follower_density: 1.0,
    seed: 42,
    time_units: 1,
    tiers: [
      %FirehoseSimulator.SimulationPlan.Params.SessionTier{
        max_followers: 1_000,
        session_minutes: 10
      }
    ]
  }

  test "generate/1 returns an in-memory sessions list" do
    sessions = Sessions.generate(@config)

    assert length(sessions) == 2
    assert Enum.all?(sessions, &is_integer(&1.offset_ms))
    assert sessions |> Enum.map(& &1.user_id) |> Enum.sort() == [1, 2]
    assert Enum.all?(sessions, &(&1.duration_ms == 600_000))
  end

  test "lookup_tier/4 honors follower_density when matching tiers" do
    tiers = [
      %FirehoseSimulator.SimulationPlan.Params.SessionTier{max_followers: 6, session_minutes: 5},
      %FirehoseSimulator.SimulationPlan.Params.SessionTier{
        max_followers: 100,
        session_minutes: 10
      }
    ]

    assert %{session_minutes: 5} = Sessions.lookup_tier(2, 10, tiers, 1.0)
    assert %{session_minutes: 10} = Sessions.lookup_tier(2, 10, tiers, 2.0)
  end

  test "generate/2 uses the provided time unit duration" do
    sessions = Sessions.generate(@config, 1_000)

    assert Enum.all?(sessions, &(&1.offset_ms < 1_000))
  end
end
