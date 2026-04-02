defmodule FirehoseSimulator.BulkCreationTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias FirehoseSimulator.BulkCreation
  alias FirehoseSimulator.DatabaseConnection
  alias FirehoseSimulator.SimulationPlan
  alias FirehoseSimulator.SimulationPlan.Userbase

  test "create_userbase/2 returns the existing connection validation error" do
    userbase = %Userbase{
      name: "not yet twitter",
      num_users: 5,
      max_active_user_id: 5,
      follower_density: 0.0
    }

    connection = %DatabaseConnection{connection_string: "not-a-url"}

    assert {:error, "Connection string must be a postgres URL"} =
             BulkCreation.create_userbase(userbase, connection)
  end

  test "create_userbase/2 surfaces connection failures for unreachable databases" do
    userbase = %Userbase{
      name: "offline import",
      num_users: 3,
      max_active_user_id: 3,
      follower_density: 5.0
    }

    connection =
      %DatabaseConnection{
        connection_string: "postgres://postgres:postgres@127.0.0.1:1/firehose_simulator_test"
      }

    capture_log(fn ->
      assert {:error, message} = BulkCreation.create_userbase(userbase, connection)
      assert is_binary(message)
      refute message == ""
    end)
  end

  test "create_simulation_plan/2 returns the existing connection validation error" do
    simulation_plan = %SimulationPlan{posts: nil, sessions: nil, follows: nil}
    connection = %DatabaseConnection{connection_string: "not-a-url"}

    assert {:error, "Connection string must be a postgres URL"} =
             BulkCreation.create_simulation_plan(simulation_plan, connection)
  end

  test "create_simulation_plan/2 surfaces connection failures for unreachable databases" do
    simulation_plan = %SimulationPlan{
      posts: [%{offset_ms: 100, user_id: 1}],
      sessions: [%{offset_ms: 0, user_id: 2, duration_ms: 60_000}],
      follows: [%{offset_ms: 50, actor_id: 1, subject_id: 2}]
    }

    connection =
      %DatabaseConnection{
        connection_string: "postgres://postgres:postgres@127.0.0.1:1/firehose_simulator_test"
      }

    capture_log(fn ->
      assert {:error, message} = BulkCreation.create_simulation_plan(simulation_plan, connection)
      assert is_binary(message)
      refute message == ""
    end)
  end
end
