defmodule FirehoseSimulator.PlayerTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog
  alias FirehoseSimulator.Player
  alias FirehoseSimulator.Scenario

  setup do
    start_supervised!({Registry, keys: :unique, name: FirehoseSimulator.Player.Registry})

    start_supervised!(
      {DynamicSupervisor, name: FirehoseSimulator.PlayerSupervisor, strategy: :one_for_one}
    )

    start_supervised!({Task.Supervisor, name: FirehoseSimulator.Player.TaskSupervisor})
    start_supervised!(FirehoseSimulator.State)
    :ok
  end

  test "emits telemetry for player lifecycle transitions" do
    load_handler = attach_handler("load", [:firehose_simulator, :player, :load])
    start_handler = attach_handler("start", [:firehose_simulator, :player, :start])
    pause_handler = attach_handler("pause", [:firehose_simulator, :player, :pause])
    stop_handler = attach_handler("stop", [:firehose_simulator, :player, :stop])

    on_exit(fn ->
      :telemetry.detach(load_handler)
      :telemetry.detach(start_handler)
      :telemetry.detach(pause_handler)
      :telemetry.detach(stop_handler)
    end)

    scenario = %Scenario{
      sessions: [%{offset_ms: 0, user_id: 1, duration_ms: 5_000}],
      posts: nil,
      follows: nil,
      request_interval_ms: 100,
      timeline_limit: 20
    }

    {:ok, player_id, _metadata} =
      Player.load(scenario, scenario_id: "scenario-1", scheduler_count: 1)

    assert_receive {:telemetry_event, [:firehose_simulator, :player, :load], %{count: 1},
                    load_metadata}

    assert load_metadata.player_id == player_id
    assert load_metadata.scenario_id == "scenario-1"
    assert load_metadata.schedulers == 1

    capture_log(fn ->
      :ok = Player.start(player_id)

      assert_receive {:telemetry_event, [:firehose_simulator, :player, :start], %{count: 1},
                      %{player_id: ^player_id, from_state: :loaded}}

      :ok = await(fn -> Player.status(player_id).active_sessions >= 1 end)
      :ok = Player.pause(player_id)

      assert_receive {:telemetry_event, [:firehose_simulator, :player, :pause], %{count: 1},
                      %{player_id: ^player_id}}

      :ok = Player.start(player_id)

      assert_receive {:telemetry_event, [:firehose_simulator, :player, :start], %{count: 1},
                      %{player_id: ^player_id, from_state: :paused}}

      active_sessions = Player.status(player_id).active_sessions
      assert active_sessions >= 1

      :ok = Player.stop(player_id)

      assert_receive {:telemetry_event, [:firehose_simulator, :player, :stop],
                      %{count: 1, active_sessions_cleared: cleared}, %{player_id: ^player_id}}

      assert cleared == active_sessions
    end)
  end

  defp attach_handler(suffix, event_name) do
    handler_id = "player-test-#{suffix}-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler_id,
      event_name,
      fn event, measurements, metadata, pid ->
        send(pid, {:telemetry_event, event, measurements, metadata})
      end,
      self()
    )

    handler_id
  end

  defp await(fun, timeout_ms \\ 1_000) when is_function(fun, 0) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_await(fun, deadline)
  end

  defp do_await(fun, deadline) do
    if fun.() do
      :ok
    else
      if System.monotonic_time(:millisecond) >= deadline do
        flunk("timed out waiting for player state")
      end

      receive do
      after
        10 -> do_await(fun, deadline)
      end
    end
  end
end
