defmodule FirehoseSimulator.Player.EventFeederTest do
  use ExUnit.Case, async: false

  alias FirehoseSimulator.Scenario
  alias FirehoseSimulator.Player.EventFeeder
  alias FirehoseSimulator.Player.Store
  alias FirehoseSimulator.Metrics

  setup do
    Phoenix.PubSub.subscribe(FirehoseSimulator.PubSub, "firehose")

    :ok
  end

  test "indexes posts and follows by emitting firehose events" do
    store_name =
      {:via, Registry, {FirehoseSimulator.Player.Registry, {"event-feeder-test", self()}}}

    store = start_supervised!({Store, [name: store_name, num_partitions: 1]})

    event_feeder =
      start_supervised!(
        {EventFeeder,
         [
           scenario: %Scenario{
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

    # wait for async task telemetry to be ingested
    Process.sleep(50)
    snapshot = Metrics.snapshot()

    assert snapshot.event_feeder_posts_dispatch_count >= 1
    assert snapshot.event_feeder_posts_dispatched >= 1
    assert snapshot.event_feeder_posts_complete_count >= 1
    assert snapshot.event_feeder_posts_ok >= 1

    assert snapshot.event_feeder_follows_dispatch_count >= 1
    assert snapshot.event_feeder_follows_dispatched >= 1
    assert snapshot.event_feeder_follows_complete_count >= 1
    assert snapshot.event_feeder_follows_ok >= 1
  end
end
