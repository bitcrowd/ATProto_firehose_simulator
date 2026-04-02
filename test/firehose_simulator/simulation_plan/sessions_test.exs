defmodule FirehoseSimulator.SimulationPlan.SessionsTest do
  use ExUnit.Case, async: false

  alias FirehoseSimulator.SimulationPlan.Sessions
  alias FirehoseSimulator.SimulationPlan.Params.SessionsParams

  @config %SessionsParams{
    n: 100,
    max_active_user_id: 2,
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
end
