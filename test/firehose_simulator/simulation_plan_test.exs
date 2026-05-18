defmodule FirehoseSimulator.SimulationPlanTest do
  use ExUnit.Case, async: false

  alias FirehoseSimulator.Scenario
  alias FirehoseSimulator.SimulationPlan
  alias FirehoseSimulator.SimulationPlan.Entry

  describe "new/1" do
    test "builds a simulation plan" do
      started_at =
        DateTime.utc_now()
        |> DateTime.truncate(:microsecond)

      assert {:ok,
              %SimulationPlan{
                name: "imported-plan",
                started_at: ^started_at,
                export_path: "/tmp/plan.json",
                entries: [
                  %Entry{
                    scenario_name: "first-scenario",
                    scenario_path: "/tmp/first-scenario.json",
                    offset_ms: 125
                  }
                ]
              }} =
               SimulationPlan.new(%{
                 "name" => "imported-plan",
                 "started_at" => DateTime.to_iso8601(started_at),
                 "export_path" => "/tmp/plan.json",
                 "entries" => [
                   %{
                     "scenario_name" => " first-scenario ",
                     "scenario_path" => " /tmp/first-scenario.json ",
                     "offset_ms" => 125
                   }
                 ]
               })
    end

    test "defaults missing entries to an empty list" do
      assert {:ok, %SimulationPlan{entries: []}} = SimulationPlan.new()
    end
  end

  describe "update/2" do
    test "replaces embedded entries when entries are provided" do
      existing_entry = %Entry{
        scenario_name: "existing-scenario",
        scenario_path: "/tmp/existing-scenario.json",
        offset_ms: 100
      }

      simulation_plan = %SimulationPlan{
        name: "current-plan",
        entries: [existing_entry]
      }

      assert {:ok,
              %SimulationPlan{
                name: "renamed-plan",
                entries: [
                  %Entry{
                    scenario_name: "replacement-scenario",
                    scenario_path: "/tmp/replacement-scenario.json",
                    offset_ms: 200
                  }
                ]
              }} =
               SimulationPlan.update(simulation_plan, %{
                 name: "renamed-plan",
                 entries: [
                   %{
                     scenario_name: "replacement-scenario",
                     scenario_path: "/tmp/replacement-scenario.json",
                     offset_ms: 200
                   }
                 ]
               })
    end

    test "preserves existing entries when entries are omitted" do
      entry = %Entry{
        scenario_name: "existing-scenario",
        scenario_path: "/tmp/existing-scenario.json",
        offset_ms: 100
      }

      simulation_plan = %SimulationPlan{
        name: "current-plan",
        entries: [entry]
      }

      assert {:ok, %SimulationPlan{name: "renamed-plan", entries: [^entry]}} =
               SimulationPlan.update(simulation_plan, %{name: "renamed-plan"})
    end
  end

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
