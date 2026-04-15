defmodule FirehoseSimulator.SimulationPlanTest do
  use ExUnit.Case, async: false

  alias FirehoseSimulator.Scenario
  alias FirehoseSimulator.SimulationPlan
  alias FirehoseSimulator.SimulationPlan.Entry

  describe "add_scenario/5" do
    test "starts a plan clock on the first scenario and preserves the submitted offset" do
      scenario = %Scenario{
        posts: [%{offset_ms: 10, user_id: 1}],
        sessions: nil,
        follows: nil,
        request_interval_ms: 30_000
      }

      assert {:ok, simulation_plan} = SimulationPlan.new(%{entries: []})

      assert {:ok, %SimulationPlan{} = updated_plan, %Entry{} = entry} =
               SimulationPlan.add_scenario(
                 simulation_plan,
                 scenario,
                 "initial-scenario",
                 250,
                 "/tmp/initial-scenario.json"
               )

      assert entry.offset_ms == 250
      assert entry.scenario_name == "initial-scenario"
      assert entry.scenario_path == "/tmp/initial-scenario.json"
      assert entry.scenario == scenario
      assert [^entry] = updated_plan.entries
    end

    test "adds elapsed plan time to later scenarios" do
      started_at = DateTime.add(DateTime.utc_now(), -2, :second)

      scenario = %Scenario{
        posts: [%{offset_ms: 10, user_id: 1}],
        sessions: nil,
        follows: nil,
        request_interval_ms: 30_000
      }

      simulation_plan = %SimulationPlan{
        started_at: started_at,
        entries: [
          %Entry{
            scenario_name: "existing-scenario",
            scenario_path: "/tmp/existing-scenario.json",
            offset_ms: 100
          }
        ]
      }

      min_offset_ms = DateTime.diff(DateTime.utc_now(), started_at, :millisecond) + 250

      assert {:ok, %SimulationPlan{} = updated_plan, %Entry{} = entry} =
               SimulationPlan.add_scenario(
                 simulation_plan,
                 scenario,
                 "later-scenario",
                 250,
                 "/tmp/later-scenario.json"
               )

      max_offset_ms = DateTime.diff(DateTime.utc_now(), started_at, :millisecond) + 250

      assert entry.offset_ms >= min_offset_ms
      assert entry.offset_ms <= max_offset_ms
      assert entry.scenario_name == "later-scenario"
      assert List.last(updated_plan.entries) == entry
      assert updated_plan.started_at == started_at
    end
  end
end
