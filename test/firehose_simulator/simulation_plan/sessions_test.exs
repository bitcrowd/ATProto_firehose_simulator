defmodule FirehoseSimulator.SimulationPlan.SessionsTest do
  use ExUnit.Case, async: false

  alias FirehoseSimulator.SimulationPlan.Sessions
  alias FirehoseSimulator.SimulationPlan.Params.SessionsParams
  alias FirehoseSimulator.SimulationPlan.CSV

  @config %SessionsParams{
    n: 100,
    max_active_user_id: 2,
    seed: 42,
    time_units: 1,
    path: "sessions.csv",
    tiers: [
      %FirehoseSimulator.SimulationPlan.Params.SessionTier{
        max_followers: 1_000,
        session_minutes: 10
      }
    ]
  }

  test "generate/1 returns an in-memory plan struct" do
    plan = Sessions.generate(@config)

    assert %Sessions{sessions: sessions} = plan
    assert length(sessions) == 2
    assert Enum.all?(sessions, &is_integer(&1.offset_ms))
    assert sessions |> Enum.map(& &1.user_id) |> Enum.sort() == [1, 2]
    assert Enum.all?(sessions, &(&1.duration_ms == 600_000))
  end

  @tag :tmp_dir
  test "CSV.write/2 and CSV.load/2 round-trip the generated sessions", %{tmp_dir: tmp_dir} do
    plan = Sessions.generate(@config)
    path = Path.join(tmp_dir, "sessions.csv")

    assert :ok = CSV.write(plan, path)

    assert File.read!(path) ==
             "offset_ms,user_id,duration_ms\n" <>
               Enum.map_join(plan.sessions, "", fn session ->
                 "#{session.offset_ms},#{session.user_id},#{session.duration_ms}\n"
               end)

    assert {:ok, loaded_sessions} = CSV.load(:sessions, path)

    assert loaded_sessions == plan.sessions
  end

  test "CSV.load/2 returns an error for missing csv" do
    path = "does-not-exist-sessions.csv"
    error_msg = "cannot read sessions csv at #{path}"

    assert {:error, ^error_msg} = CSV.load(:sessions, path)
  end
end
