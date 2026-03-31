defmodule FirehoseSimulator.BulkCreation.State do
  use GenServer

  alias FirehoseSimulator.BulkCreation
  alias FirehoseSimulator.BulkCreation.DynamicRepo
  alias FirehoseSimulator.BulkCreation.RepoSupervisor

  def start_link(arg) do
    GenServer.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def connect(connection_string) do
    GenServer.call(__MODULE__, {:connect, connection_string}, 30_000)
  end

  def current_state do
    GenServer.call(__MODULE__, :current_state)
  end

  def reserve(type, amount)
      when type in [:posts, :follows] and is_integer(amount) and amount > 0 do
    GenServer.call(__MODULE__, {:reserve, type, amount})
  end

  def sync_ids(max_user_id, max_post_sequence) do
    GenServer.call(__MODULE__, {:sync_ids, max_user_id, max_post_sequence})
  end

  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  @impl true
  def init(_arg) do
    {:ok,
     %{
       current_connection_string: nil,
       current_repo_name: nil,
       repo_pid: nil,
       counters: %{}
     }}
  end

  @impl true
  def handle_call(:current_state, _from, state) do
    current =
      case state.current_connection_string do
        nil ->
          %{connected?: false}

        connection_string ->
          counter_state =
            Map.get(state.counters, connection_string, %{last_post_sequence: 0, last_user_id: 0})

          %{
            connected?: true,
            connection_string: connection_string,
            last_user_id: counter_state.last_user_id,
            last_post_sequence: counter_state.last_post_sequence
          }
      end

    {:reply, current, state}
  end

  def handle_call(:reset, _from, state) do
    state = stop_current_repo(state)
    {:reply, :ok, %{state | counters: %{}}}
  end

  def handle_call({:connect, connection_string}, _from, state) do
    connection_string = String.trim(connection_string)

    with :ok <- validate_connection_string(connection_string),
         {:ok, state} <- ensure_repo_started(state, connection_string) do
      counters = Map.get(state.counters, connection_string, default_counters())
      state = put_in(state.counters[connection_string], counters)

      {:reply,
       {:ok,
        %{
          connection_string: connection_string,
          last_user_id: counters.last_user_id,
          last_post_sequence: counters.last_post_sequence
        }}, state}
    else
      {:error, _reason} = error -> {:reply, error, state}
    end
  end

  def handle_call({:reserve, type, amount}, _from, state) do
    case state.current_connection_string do
      nil ->
        {:reply, {:error, :not_connected}, state}

      connection_string ->
        counters =
          Map.get(state.counters, connection_string, %{last_post_sequence: 0, last_user_id: 0})

        case type do
          :posts ->
            reserved = %{
              last_user_id: counters.last_user_id + amount,
              last_post_sequence: counters.last_post_sequence + amount
            }

            new_counters = %{
              counters
              | last_user_id: reserved.last_user_id,
                last_post_sequence: reserved.last_post_sequence
            }

            state = put_in(state.counters[connection_string], new_counters)
            {:reply, {:ok, reserved}, state}

          :follows ->
            reserved = %{
              last_user_id: counters.last_user_id + amount,
              last_post_sequence: counters.last_post_sequence
            }

            new_counters = %{counters | last_user_id: reserved.last_user_id}

            state = put_in(state.counters[connection_string], new_counters)
            {:reply, {:ok, reserved}, state}
        end
    end
  end

  def handle_call({:sync_ids, max_user_id, max_post_sequence}, _from, state) do
    case state.current_connection_string do
      nil ->
        {:reply, {:error, :not_connected}, state}

      connection_string ->
        counters =
          Map.get(state.counters, connection_string, %{last_post_sequence: 0, last_user_id: 0})

        new_counters = %{
          last_user_id: max(counters.last_user_id, max_user_id),
          last_post_sequence: max(counters.last_post_sequence, max_post_sequence)
        }

        state = put_in(state.counters[connection_string], new_counters)
        {:reply, {:ok, new_counters}, state}
    end
  end

  defp validate_connection_string(""), do: {:error, "Connection string is required"}
  defp validate_connection_string("postgres://" <> _rest), do: :ok
  defp validate_connection_string("ecto://" <> _rest), do: :ok
  defp validate_connection_string(_), do: {:error, "Connection string must be a postgres URL"}

  defp default_counters do
    %{last_post_sequence: 0, last_user_id: 0}
  end

  defp ensure_repo_started(
         %{current_connection_string: connection_string} = state,
         connection_string
       ) do
    {:ok, state}
  end

  defp ensure_repo_started(state, connection_string) do
    state = stop_current_repo(state)
    repo_name = BulkCreation.repo_name(connection_string)

    child_spec = %{
      id: repo_name,
      start:
        {DynamicRepo, :start_link,
         [
           [
             name: repo_name,
             url: connection_string,
             pool_size: 2,
             stacktrace: true,
             show_sensitive_data_on_connection_error: true
           ]
         ]}
    }

    case DynamicSupervisor.start_child(RepoSupervisor, child_spec) do
      {:ok, repo_pid} ->
        case BulkCreation.ping(repo_name) do
          :ok ->
            {:ok,
             %{
               state
               | current_connection_string: connection_string,
                 current_repo_name: repo_name,
                 repo_pid: repo_pid
             }}

          {:error, error} ->
            _ = DynamicSupervisor.terminate_child(RepoSupervisor, repo_pid)
            {:error, normalize_error(error)}
        end

      {:error, {:already_started, repo_pid}} ->
        {:ok,
         %{
           state
           | current_connection_string: connection_string,
             current_repo_name: repo_name,
             repo_pid: repo_pid
         }}

      {:error, error} ->
        {:error, normalize_error(error)}
    end
  end

  defp stop_current_repo(%{repo_pid: nil} = state), do: state

  defp stop_current_repo(%{repo_pid: repo_pid} = state) do
    _ = DynamicSupervisor.terminate_child(RepoSupervisor, repo_pid)
    %{state | current_repo_name: nil, current_connection_string: nil, repo_pid: nil}
  end

  defp normalize_error(error) when is_binary(error), do: error
  defp normalize_error(%_{} = error), do: Exception.message(error)
  defp normalize_error(error), do: inspect(error)
end
