defmodule FirehoseSimulator.EventFeederTest do
  use ExUnit.Case, async: false

  alias FirehoseSimulator.SimulationPlan
  alias FirehoseSimulator.SimulationPlan.EventFeeder
  alias FirehoseSimulator.SimulationPlan.Follows
  alias FirehoseSimulator.SimulationPlan.Posts
  alias FirehoseSimulator.Store

  setup do
    stop_if_running(EventFeeder)
    stop_if_running(Store)

    Phoenix.PubSub.subscribe(FirehoseSimulator.PubSub, "firehose")

    on_exit(fn ->
      stop_if_running(EventFeeder)
      stop_if_running(Store)
    end)

    :ok
  end

  test "indexes posts and follows by emitting firehose events" do
    start_supervised!({Store, []})

    start_supervised!(
      {EventFeeder,
       [
         simulation_plan: %SimulationPlan{
           sessions_plan: nil,
           posts_plan: %Posts{posts: [%{offset_ms: 0, user_id: 1}]},
           follows_plan: %Follows{follows: [%{offset_ms: 0, actor_id: 2, subject_id: 1}]}
         },
         request_interval_ms: 10,
         scheduler_count: 1
       ]}
    )

    :ok = EventFeeder.start_feeding()
    send(EventFeeder, :check)

    assert_receive [_, _], 1_000
    assert_receive [_, _], 1_000
  end

  defp stop_if_running(name) do
    case Process.whereis(name) do
      nil ->
        :ok

      pid ->
        ref = Process.monitor(pid)
        Process.exit(pid, :shutdown)
        assert_receive {:DOWN, ^ref, :process, ^pid, _reason}
        :ok
    end
  end
end
