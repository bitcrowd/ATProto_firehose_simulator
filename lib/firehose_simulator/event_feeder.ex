defmodule FirehoseSimulator.SimulationPlan.EventFeeder do
  @moduledoc """
  GenServer that injects events from a `%FirehoseSimulator.SimulationPlan{}` over wallclock time.
  """
  use GenServer

  require Logger

  alias FirehoseSimulator.Data
  alias FirehoseSimulator.Event
  alias FirehoseSimulator.Session
  alias FirehoseSimulator.SimulationPlan
  alias FirehoseSimulator.SimulationPlan.Follows
  alias FirehoseSimulator.SimulationPlan.Posts
  alias FirehoseSimulator.SimulationPlan.Sessions
  alias FirehoseSimulator.Store
  alias Phoenix.PubSub

  @check_interval_ms 100
  @post_batch_concurrency 10
  @follow_batch_concurrency 10

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def start_feeding do
    GenServer.cast(__MODULE__, :start)
  end

  def load_plan(%SimulationPlan{} = simulation_plan, opts \\ []) do
    GenServer.call(__MODULE__, {:load_plan, simulation_plan, opts}, :infinity)
  end

  def status do
    GenServer.call(__MODULE__, :status, :infinity)
  end

  @impl true
  def init(opts) do
    simulation_plan = Keyword.fetch!(opts, :simulation_plan)
    request_interval_ms = Keyword.fetch!(opts, :request_interval_ms)
    scheduler_count = Keyword.fetch!(opts, :scheduler_count)
    time_offset_ms = Keyword.get(opts, :time_offset_ms, 0)

    Store.ensure_partition_tables(scheduler_count)

    {sessions, posts, follows} = plan_events(simulation_plan, time_offset_ms)

    Logger.info(
      "[EventFeeder] Loaded #{length(sessions)} sessions, #{length(posts)} posts, #{length(follows)} follows"
    )

    {:ok,
     %{
       sessions: sessions,
       posts: posts,
       follows: follows,
       request_interval_ms: request_interval_ms,
       scheduler_count: scheduler_count,
       next_session_id: 1,
       started_at: nil,
       post_task: nil,
       follow_task: nil
     }}
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = %{
      started?: state.started_at != nil,
      pending: %{
        sessions: length(state.sessions),
        posts: length(state.posts),
        follows: length(state.follows)
      }
    }

    {:reply, status, state}
  end

  def handle_call({:load_plan, simulation_plan, opts}, _from, state) do
    time_offset_ms = Keyword.get(opts, :time_offset_ms, 0)
    {new_sessions, new_posts, new_follows} = plan_events(simulation_plan, time_offset_ms)

    sessions = merge_sorted_events(state.sessions, new_sessions, fn {offset, _, _} -> offset end)
    posts = merge_sorted_events(state.posts, new_posts, fn {offset, _} -> offset end)
    follows = merge_sorted_events(state.follows, new_follows, fn {offset, _, _} -> offset end)

    Logger.info(
      "[EventFeeder] Appended #{length(new_sessions)} sessions, #{length(new_posts)} posts, #{length(new_follows)} follows"
    )

    reply = %{
      sessions: length(new_sessions),
      posts: length(new_posts),
      follows: length(new_follows)
    }

    {:reply, {:ok, reply}, %{state | sessions: sessions, posts: posts, follows: follows}}
  end

  @impl true
  def handle_cast(:start, %{started_at: nil} = state) do
    now = System.monotonic_time(:millisecond)
    Logger.info("[EventFeeder] Started")
    schedule_check()
    {:noreply, %{state | started_at: now}}
  end

  def handle_cast(:start, state), do: {:noreply, state}

  @impl true
  def handle_info(:check, %{started_at: nil} = state) do
    {:noreply, state}
  end

  def handle_info(:check, state) do
    now = System.monotonic_time(:millisecond)
    elapsed_ms = now - state.started_at

    {state, sessions_started} = process_sessions(state, elapsed_ms)
    state = maybe_dispatch_posts(state, elapsed_ms)
    state = maybe_dispatch_follows(state, elapsed_ms)

    if sessions_started > 0 do
      :telemetry.execute(
        [:feed_simulator, :event_feeder, :inject],
        %{
          sessions_started: sessions_started,
          posts_ok: 0,
          posts_error: 0,
          follows_ok: 0,
          follows_error: 0
        },
        %{elapsed_ms: elapsed_ms}
      )
    end

    schedule_check()
    {:noreply, state}
  end

  def handle_info({ref, post_results}, %{post_task: ref} = state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])

    :telemetry.execute(
      [:feed_simulator, :event_feeder, :inject],
      %{
        sessions_started: 0,
        posts_ok: post_results.ok,
        posts_error: post_results.error,
        follows_ok: 0,
        follows_error: 0
      },
      %{}
    )

    {:noreply, %{state | post_task: nil}}
  end

  def handle_info({ref, follow_results}, %{follow_task: ref} = state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])

    :telemetry.execute(
      [:feed_simulator, :event_feeder, :inject],
      %{
        sessions_started: 0,
        posts_ok: 0,
        posts_error: 0,
        follows_ok: follow_results.ok,
        follows_error: follow_results.error
      },
      %{}
    )

    {:noreply, %{state | follow_task: nil}}
  end

  def handle_info({:DOWN, ref, :process, _pid, :normal}, state) do
    state =
      cond do
        state.post_task == ref -> %{state | post_task: nil}
        state.follow_task == ref -> %{state | follow_task: nil}
        true -> state
      end

    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    state =
      cond do
        state.post_task == ref ->
          Logger.error("[EventFeeder] post batch task crashed: #{inspect(reason)}")
          %{state | post_task: nil}

        state.follow_task == ref ->
          Logger.error("[EventFeeder] follow batch task crashed: #{inspect(reason)}")
          %{state | follow_task: nil}

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

  defp process_sessions(state, elapsed_ms) do
    {due, remaining} =
      Enum.split_while(state.sessions, fn {offset, _uid, _dur} -> offset <= elapsed_ms end)

    {next_id, _} =
      Enum.reduce(due, {state.next_session_id, state.scheduler_count}, fn {_offset, user_id,
                                                                           duration_ms},
                                                                          {sid, sc} ->
        session =
          Session.new(
            id: sid,
            user_id: user_id,
            duration_ms: duration_ms,
            request_interval_ms: state.request_interval_ms
          )

        partition = rem(:erlang.phash2(sid), sc)
        :ets.insert(Store.table_name(partition), {sid, session})

        {sid + 1, sc}
      end)

    {%{state | sessions: remaining, next_session_id: next_id}, length(due)}
  end

  defp maybe_dispatch_posts(%{post_task: task} = state, _elapsed_ms) when task != nil do
    state
  end

  defp maybe_dispatch_posts(state, elapsed_ms) do
    {due, remaining} =
      Enum.split_while(state.posts, fn {offset, _uid} -> offset <= elapsed_ms end)

    if due == [] do
      %{state | posts: remaining}
    else
      task =
        Task.async(fn ->
          due
          |> Task.async_stream(
            fn {_offset, user_id} -> {user_id, emit_post_event(user_id)} end,
            max_concurrency: @post_batch_concurrency,
            timeout: 30_000,
            on_timeout: :kill_task
          )
          |> Enum.reduce(%{ok: 0, error: 0}, fn
            {:ok, {_user_id, :ok}}, acc ->
              %{acc | ok: acc.ok + 1}

            {:ok, {user_id, {:error, reason}}}, acc ->
              Logger.warning(
                "[EventFeeder] create_post failed for user #{user_id}: #{inspect(reason)}"
              )

              %{acc | error: acc.error + 1}

            {:exit, reason}, acc ->
              Logger.error("[EventFeeder] create_post task crashed: #{inspect(reason)}")
              %{acc | error: acc.error + 1}
          end)
        end)

      %{state | posts: remaining, post_task: task.ref}
    end
  end

  defp maybe_dispatch_follows(%{follow_task: task} = state, _elapsed_ms) when task != nil do
    state
  end

  defp maybe_dispatch_follows(state, elapsed_ms) do
    {due, remaining} =
      Enum.split_while(state.follows, fn {offset, _actor_id, _subject_id} ->
        offset <= elapsed_ms
      end)

    if due == [] do
      %{state | follows: remaining}
    else
      task =
        Task.async(fn ->
          due
          |> Task.async_stream(
            fn {_offset, actor_id, subject_id} ->
              {{actor_id, subject_id}, emit_follow_event(actor_id, subject_id)}
            end,
            max_concurrency: @follow_batch_concurrency,
            timeout: 30_000,
            on_timeout: :kill_task
          )
          |> Enum.reduce(%{ok: 0, error: 0}, fn
            {:ok, {{_actor_id, _subject_id}, :ok}}, acc ->
              %{acc | ok: acc.ok + 1}

            {:ok, {{actor_id, subject_id}, {:error, reason}}}, acc ->
              Logger.warning(
                "[EventFeeder] toggle_follow failed for #{actor_id}->#{subject_id}: #{inspect(reason)}"
              )

              %{acc | error: acc.error + 1}

            {:exit, reason}, acc ->
              Logger.error("[EventFeeder] toggle_follow task crashed: #{inspect(reason)}")
              %{acc | error: acc.error + 1}
          end)
        end)

      %{state | follows: remaining, follow_task: task.ref}
    end
  end

  defp plan_events(%SimulationPlan{} = simulation_plan, time_offset_ms) do
    sessions = sessions_from_plan(simulation_plan.sessions_plan, time_offset_ms)
    posts = posts_from_plan(simulation_plan.posts_plan, time_offset_ms)
    follows = follows_from_plan(simulation_plan.follows_plan, time_offset_ms)
    {sessions, posts, follows}
  end

  defp sessions_from_plan(nil, _time_offset_ms), do: []

  defp sessions_from_plan(%Sessions{sessions: sessions}, time_offset_ms) do
    sessions
    |> Enum.map(fn %{offset_ms: offset_ms, user_id: user_id, duration_ms: duration_ms} ->
      {offset_ms + time_offset_ms, user_id, duration_ms}
    end)
    |> Enum.sort_by(fn {offset, _uid, _dur} -> offset end)
  end

  defp posts_from_plan(nil, _time_offset_ms), do: []

  defp posts_from_plan(%Posts{posts: posts}, time_offset_ms) do
    posts
    |> Enum.map(fn %{offset_ms: offset_ms, user_id: user_id} ->
      {offset_ms + time_offset_ms, user_id}
    end)
    |> Enum.sort_by(fn {offset, _uid} -> offset end)
  end

  defp follows_from_plan(nil, _time_offset_ms), do: []

  defp follows_from_plan(%Follows{follows: follows}, time_offset_ms) do
    follows
    |> Enum.map(fn %{offset_ms: offset_ms, actor_id: actor_id, subject_id: subject_id} ->
      {offset_ms + time_offset_ms, actor_id, subject_id}
    end)
    |> Enum.sort_by(fn {offset, _actor_id, _subject_id} -> offset end)
  end

  defp merge_sorted_events(existing, new_events, key_fun) do
    (existing ++ new_events)
    |> Enum.sort_by(key_fun)
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
    :ok
  rescue
    error -> {:error, error}
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
    :ok
  rescue
    error -> {:error, error}
  end
end
