defmodule FirehoseSimulator.Scenario.SessionsTest do
  use ExUnit.Case, async: false

  alias FirehoseSimulator.Scenario.Params.SessionsParams
  alias FirehoseSimulator.Scenario.Sessions

  @config %SessionsParams{
    num_users: 100,
    max_active_user_id: 2,
    follower_density: 1.0,
    tiers: [
      %FirehoseSimulator.Scenario.Params.SessionTier{
        max_followers: 1_000,
        session_minutes: 10
      }
    ]
  }

  test "generate/4 returns an in-memory sessions list" do
    sessions = Sessions.generate(@config, 42, 1)

    assert length(sessions) == 2
    assert Enum.all?(sessions, &is_integer(&1.offset_ms))
    assert sessions |> Enum.map(& &1.user_id) |> Enum.sort() == [1, 2]
    assert Enum.all?(sessions, &(&1.duration_ms == 600_000))
  end

  test "generate/4 uses the provided time unit duration" do
    sessions = Sessions.generate(@config, 42, 1, 1_000)

    assert Enum.all?(sessions, &(&1.offset_ms < 1_000))
  end
end
