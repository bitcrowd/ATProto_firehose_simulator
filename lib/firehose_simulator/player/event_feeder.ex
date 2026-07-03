defmodule FirehoseSimulator.Player.EventFeeder do
  @moduledoc """
  GenServer that injects events from a `%FirehoseSimulator.Scenario{}` over wallclock time.
  """
  use GenServer
  alias FirehoseSimulator.Data
  alias FirehoseSimulator.Player.Event
  alias FirehoseSimulator.Player.Store
  alias FirehoseSimulator.Scenario
  alias Phoenix.PubSub
  require Logger

  @check_interval_ms 100

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def start(event_feeder) do
    GenServer.call(event_feeder, :start, :infinity)
  end

  def pause(event_feeder) do
    GenServer.call(event_feeder, :pause, :infinity)
  end

  def status(event_feeder) do
    GenServer.call(event_feeder, :status, :infinity)
  end

  @impl true
  def init(opts) do
    player_id = Keyword.get(opts, :player_id)
    scenario = Keyword.fetch!(opts, :scenario)
    store = Keyword.fetch!(opts, :store)
    request_interval_ms = Keyword.fetch!(opts, :request_interval_ms)
    scheduler_count = Keyword.fetch!(opts, :scheduler_count)

    partition_tables = Store.partition_tables(store)

    {sessions, posts, follows} = scenario_events(scenario)

    Logger.info(
      "[EventFeeder] Loaded #{length(sessions)} sessions, #{length(posts)} posts, #{length(follows)} follows"
    )

    {:ok,
     %{
       player_id: player_id,
       lifecycle_state: :loaded,
       sessions: sessions,
       posts: posts,
       follows: follows,
       partition_tables: partition_tables,
       request_interval_ms: request_interval_ms,
       scheduler_count: scheduler_count,
       next_session_id: 1,
       started_at: nil,
       paused_at: nil,
       total_paused: 0,
       post_tasks: [],
       follow_tasks: []
     }}
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = %{
      lifecycle_state: state.lifecycle_state,
      started?: state.started_at != nil,
      effective_elapsed: effective_elapsed(state),
      pending: %{
        sessions: length(state.sessions),
        posts: length(state.posts),
        follows: length(state.follows)
      }
    }

    {:reply, status, state}
  end

  def handle_call(:start, _from, %{lifecycle_state: :running} = state) do
    {:reply, {:error, {:invalid_state_transition, :running, :start}}, state}
  end

  def handle_call(:start, _from, %{lifecycle_state: :loaded} = state) do
    now = System.monotonic_time(:millisecond)
    Logger.info("[EventFeeder] Started")
    schedule_check()

    {:reply, :ok,
     %{state | lifecycle_state: :running, started_at: now, paused_at: nil, total_paused: 0}}
  end

  def handle_call(:start, _from, %{lifecycle_state: :paused} = state) do
    now = System.monotonic_time(:millisecond)
    schedule_check()

    {:reply, :ok,
     %{
       state
       | lifecycle_state: :running,
         paused_at: nil,
         total_paused: state.total_paused + (now - state.paused_at)
     }}
  end

  def handle_call(:pause, _from, %{lifecycle_state: :running} = state) do
    now = System.monotonic_time(:millisecond)
    {:reply, :ok, %{state | lifecycle_state: :paused, paused_at: now}}
  end

  def handle_call(:pause, _from, %{lifecycle_state: lifecycle_state} = state) do
    {:reply, {:error, {:invalid_state_transition, lifecycle_state, :pause}}, state}
  end

  @impl true
  def handle_info(:check, %{lifecycle_state: lifecycle_state} = state)
      when lifecycle_state in [:loaded, :paused] do
    {:noreply, state}
  end

  def handle_info(:check, state) do
    elapsed_ms = effective_elapsed(state)

    {state, sessions_started} = process_sessions(state, elapsed_ms)
    state = maybe_dispatch_posts(state, elapsed_ms)
    state = maybe_dispatch_follows(state, elapsed_ms)

    if sessions_started > 0 do
      :telemetry.execute(
        [:firehose_simulator, :event_feeder, :inject],
        %{sessions_started: sessions_started},
        telemetry_metadata(state, %{elapsed_ms: elapsed_ms})
      )
    end

    schedule_check()
    {:noreply, state}
  end

  def handle_info({ref, results}, state) when is_reference(ref) do
    cond do
      ref in state.post_tasks ->
        Process.demonitor(ref, [:flush])

        :telemetry.execute(
          [:firehose_simulator, :event_feeder, :posts, :complete],
          %{ok: results.ok, error: results.error},
          telemetry_metadata(state, %{})
        )

        {:noreply, %{state | post_tasks: List.delete(state.post_tasks, ref)}}

      ref in state.follow_tasks ->
        Process.demonitor(ref, [:flush])

        :telemetry.execute(
          [:firehose_simulator, :event_feeder, :follows, :complete],
          %{ok: results.ok, error: results.error},
          telemetry_metadata(state, %{})
        )

        {:noreply, %{state | follow_tasks: List.delete(state.follow_tasks, ref)}}

      true ->
        {:noreply, state}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, :normal}, state) do
    state =
      cond do
        ref in state.post_tasks -> %{state | post_tasks: List.delete(state.post_tasks, ref)}
        ref in state.follow_tasks -> %{state | follow_tasks: List.delete(state.follow_tasks, ref)}
        true -> state
      end

    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    state =
      cond do
        ref in state.post_tasks ->
          Logger.error("[EventFeeder] post batch task crashed: #{inspect(reason)}")
          %{state | post_tasks: List.delete(state.post_tasks, ref)}

        ref in state.follow_tasks ->
          Logger.error("[EventFeeder] follow batch task crashed: #{inspect(reason)}")
          %{state | follow_tasks: List.delete(state.follow_tasks, ref)}

        true ->
          state
      end

    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check, @check_interval_ms)
  end

  defp effective_elapsed(%{started_at: nil}), do: 0

  defp effective_elapsed(%{
         lifecycle_state: :paused,
         paused_at: paused_at,
         started_at: started_at,
         total_paused: total_paused
       }),
       do: max(paused_at - started_at - total_paused, 0)

  defp effective_elapsed(%{started_at: started_at, total_paused: total_paused}) do
    now = System.monotonic_time(:millisecond)
    max(now - started_at - total_paused, 0)
  end

  defp telemetry_metadata(%{player_id: player_id}, metadata) when is_binary(player_id) do
    Map.put(metadata, :player_id, player_id)
  end

  defp telemetry_metadata(_state, metadata), do: metadata

  defp process_sessions(state, elapsed_ms) do
    {due, remaining} =
      Enum.split_while(state.sessions, fn {offset, _uid, _dur} -> offset <= elapsed_ms end)

    {next_id, _} =
      Enum.reduce(due, {state.next_session_id, state.scheduler_count}, fn {_offset, user_id,
                                                                           duration_ms},
                                                                          {sid, sc} ->
        session =
          new_session(
            sid,
            duration_ms,
            state.request_interval_ms,
            user_id
          )

        partition = rem(:erlang.phash2(sid), sc)
        table = Map.fetch!(state.partition_tables, partition)
        Store.put_session(table, session)

        {sid + 1, sc}
      end)

    {%{state | sessions: remaining, next_session_id: next_id}, length(due)}
  end

  defp maybe_dispatch_posts(state, elapsed_ms) do
    {due, remaining} =
      Enum.split_while(state.posts, fn {offset, _uid} -> offset <= elapsed_ms end)

    if due == [] do
      %{state | posts: remaining}
    else
      :telemetry.execute(
        [:firehose_simulator, :event_feeder, :posts, :dispatch],
        %{events_dispatched: length(due)},
        telemetry_metadata(state, %{elapsed_ms: elapsed_ms})
      )

      task =
        Task.Supervisor.async_nolink(
          FirehoseSimulator.Player.TaskSupervisor,
          fn -> dispatch_posts(due) end
        )

      %{state | posts: remaining, post_tasks: [task.ref | state.post_tasks]}
    end
  end

  defp maybe_dispatch_follows(state, elapsed_ms) do
    {due, remaining} =
      Enum.split_while(state.follows, fn {offset, _actor_id, _subject_id} ->
        offset <= elapsed_ms
      end)

    if due == [] do
      %{state | follows: remaining}
    else
      :telemetry.execute(
        [:firehose_simulator, :event_feeder, :follows, :dispatch],
        %{events_dispatched: length(due)},
        telemetry_metadata(state, %{elapsed_ms: elapsed_ms})
      )

      task =
        Task.Supervisor.async_nolink(
          FirehoseSimulator.Player.TaskSupervisor,
          fn -> dispatch_follows(due) end
        )

      %{state | follows: remaining, follow_tasks: [task.ref | state.follow_tasks]}
    end
  end

  defp scenario_events(%Scenario{} = scenario) do
    sessions = sessions_from_scenario(scenario.sessions)
    posts = posts_from_scenario(scenario.posts)
    follows = follows_from_scenario(scenario.follows)
    {sessions, posts, follows}
  end

  defp sessions_from_scenario(nil), do: []

  defp sessions_from_scenario(sessions) when is_list(sessions) do
    sessions
    |> Enum.map(fn %{offset_ms: offset_ms, user_id: user_id, duration_ms: duration_ms} ->
      {offset_ms, user_id, duration_ms}
    end)
    |> Enum.sort_by(fn {offset, _uid, _dur} -> offset end)
  end

  defp posts_from_scenario(nil), do: []

  defp posts_from_scenario(posts) when is_list(posts) do
    posts
    |> Enum.map(fn %{offset_ms: offset_ms, user_id: user_id} ->
      {offset_ms, user_id}
    end)
    |> Enum.sort_by(fn {offset, _uid} -> offset end)
  end

  defp follows_from_scenario(nil), do: []

  defp follows_from_scenario(follows) when is_list(follows) do
    follows
    |> Enum.map(fn %{offset_ms: offset_ms, actor_id: actor_id, subject_id: subject_id} ->
      {offset_ms, actor_id, subject_id}
    end)
    |> Enum.sort_by(fn {offset, _actor_id, _subject_id} -> offset end)
  end

  defp emit_post_event(user_id) do
    author_did = Data.did_for_user_id(user_id)

    payload =
      Event.from_config(%{
        "type" => Data.post_type(),
        "random" => false,
        "author_did" => author_did,
        "text" => "Simulated post from user #{user_id}"
      })

    PubSub.broadcast(FirehoseSimulator.PubSub, "firehose", payload)
  end

  defp dispatch_posts(due) do
    Enum.reduce(due, %{ok: 0, error: 0}, fn {_offset, user_id}, acc ->
      emit_result = emit_post_event(user_id)

      accumulate_post_dispatch(acc, user_id, emit_result)
    end)
  end

  defp dispatch_follows(due) do
    Enum.reduce(due, %{ok: 0, error: 0}, fn {_offset, actor_id, subject_id}, acc ->
      emit_result = emit_follow_event(actor_id, subject_id)

      accumulate_follow_dispatch(
        acc,
        actor_id,
        subject_id,
        emit_result
      )
    end)
  end

  defp accumulate_post_dispatch(acc, _user_id, :ok), do: %{acc | ok: acc.ok + 1}

  defp accumulate_post_dispatch(acc, user_id, {:error, reason}) do
    Logger.warning("[EventFeeder] emit post failed for user #{user_id}: #{inspect(reason)}")
    %{acc | error: acc.error + 1}
  end

  defp accumulate_follow_dispatch(acc, _actor_id, _subject_id, :ok),
    do: %{acc | ok: acc.ok + 1}

  defp accumulate_follow_dispatch(acc, actor_id, subject_id, {:error, reason}) do
    Logger.warning(
      "[EventFeeder] emit follow failed for #{actor_id}->#{subject_id}: #{inspect(reason)}"
    )

    %{acc | error: acc.error + 1}
  end

  defp emit_follow_event(actor_id, subject_id) do
    payload =
      Event.from_config(%{
        "type" => Data.follow_type(),
        "random" => false,
        "author_did" => Data.did_for_user_id(actor_id),
        "subject_did" => Data.did_for_user_id(subject_id)
      })

    PubSub.broadcast(FirehoseSimulator.PubSub, "firehose", payload)
  end

  defp new_session(id, duration_ms, interval, user_id) do
    now = System.monotonic_time(:millisecond)

    %{
      id: id,
      user_id: user_id,
      duration_ms: duration_ms,
      request_interval_ms: interval,
      next_request_at: now + rem(id, interval),
      expires_at: now + duration_ms,
      started_at: now
    }
  end
end
