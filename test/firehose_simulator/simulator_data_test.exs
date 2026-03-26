defmodule FirehoseSimulator.DataSimulatorMarkersTest do
  use ExUnit.Case, async: true

  alias FirehoseSimulator.Data

  test "random_did uses the simulator prefix" do
    assert did = Data.random_did()
    assert String.starts_with?(did, Data.did_prefix())
    assert Data.simulator_did?(did)
  end

  test "mark_post_text is idempotent" do
    marked = Data.mark_post_text("hello")

    assert marked == "[sim] hello"
    assert Data.mark_post_text(marked) == marked
  end
end
