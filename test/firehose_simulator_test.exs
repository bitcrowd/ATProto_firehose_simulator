defmodule FirehoseSimulatorTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias FirehoseSimulator.DatabaseConnection

  describe "create_userbase/2" do
    test "returns file load errors before attempting database work" do
      connection = %DatabaseConnection{connection_string: "postgres://example"}

      capture_log(fn ->
        assert {:error, "cannot read userbase file at missing-userbase.json"} =
                 FirehoseSimulator.create_userbase("missing-userbase.json", connection)
      end)
    end
  end
end
