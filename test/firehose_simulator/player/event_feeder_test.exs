defmodule FirehoseSimulator.Player.EventFeederTest do
  use ExUnit.Case, async: false

  alias FirehoseSimulator.Metrics
  alias FirehoseSimulator.Player.EventFeeder
  alias FirehoseSimulator.Player.Store
  alias FirehoseSimulator.Scenario

  setup do
    Phoenix.PubSub.subscribe(FirehoseSimulator.PubSub, "firehose")

    test_pid = self()
    handler_id = "event-feeder-complete-#{System.unique_integer([:positive])}"

    :telemetry.attach_many(
      handler_id,
      [
        [:firehose_simulator, :event_feeder, :posts, :complete],
        [:firehose_simulator, :event_feeder, :follows, :complete]
      ],
      fn event, _measurements, _metadata, _ -> send(test_pid, {:telemetry_complete, event}) end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

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

    assert %{lifecycle_state: :loaded, started?: false} = EventFeeder.status(event_feeder)

    :ok = EventFeeder.start(event_feeder)
    send(event_feeder, :check)

    assert_receive [_, _], 1_000
    assert_receive [_, _], 1_000

    assert_receive {:telemetry_complete, [:firehose_simulator, :event_feeder, :posts, :complete]},
                   1_000

    assert_receive {:telemetry_complete, [:firehose_simulator, :event_feeder, :follows, :complete]},
                   1_000

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
