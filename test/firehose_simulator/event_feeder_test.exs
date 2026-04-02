defmodule FirehoseSimulator.EventFeederTest do
  use ExUnit.Case, async: false

  alias FirehoseSimulator.SimulationPlan
  alias FirehoseSimulator.SimulationPlan.EventFeeder
  alias FirehoseSimulator.Store

  setup do
    Phoenix.PubSub.subscribe(FirehoseSimulator.PubSub, "firehose")

    :ok
  end

  test "indexes posts and follows by emitting firehose events" do
    store_name =
      {:via, Registry, {FirehoseSimulator.Player.Registry, {"event-feeder-test", self()}}}

    store = start_supervised!({Store, [name: store_name]})

    event_feeder =
      start_supervised!(
        {EventFeeder,
         [
           simulation_plan: %SimulationPlan{
             sessions: nil,
             posts: [%{offset_ms: 0, user_id: 1}],
             follows: [%{offset_ms: 0, actor_id: 2, subject_id: 1}]
           },
           store: store,
           request_interval_ms: 10,
           scheduler_count: 1
         ]}
      )

    :ok = EventFeeder.start_feeding(event_feeder)
    send(event_feeder, :check)

    assert_receive [_, _], 1_000
    assert_receive [_, _], 1_000
  end
end
