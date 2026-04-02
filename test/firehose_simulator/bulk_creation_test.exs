defmodule FirehoseSimulator.BulkCreationTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias FirehoseSimulator.BulkCreation
  alias FirehoseSimulator.DatabaseConnection
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
end
