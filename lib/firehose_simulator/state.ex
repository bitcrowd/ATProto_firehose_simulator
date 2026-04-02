defmodule FirehoseSimulator.State do
  @moduledoc false

  use GenServer

  alias FirehoseSimulator.SimulationPlan

  @default_connection_string "postgres://postgres:postgres@localhost:5432/atproto_blacksky?options=-csearch_path%3Dbsky"

  @type state :: %{
          db_connection_string: String.t(),
          simulation_plans: %{optional(String.t()) => SimulationPlan.t()},
          selected_simulation_plan_id: String.t() | nil,
          player_ids: map(),
          userbase_uploaded?: boolean(),
          userbase_result: map() | nil
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  @spec get() :: state()
  def get do
    GenServer.call(__MODULE__, :get_state)
  end

  @spec get_db_connection_string() :: String.t()
  def get_db_connection_string do
    GenServer.call(__MODULE__, :get_db_connection_string)
  end

  @spec put_db_connection_string(String.t()) :: :ok
  def put_db_connection_string(connection_string) when is_binary(connection_string) do
    GenServer.call(__MODULE__, {:put_db_connection_string, connection_string})
  end

  @spec put_simulation_plan(String.t(), SimulationPlan.t()) :: :ok
  def put_simulation_plan(plan_id, %SimulationPlan{} = simulation_plan) when is_binary(plan_id) do
    GenServer.call(__MODULE__, {:put_simulation_plan, plan_id, simulation_plan})
  end

  @spec delete_simulation_plan(String.t()) :: :ok
  def delete_simulation_plan(plan_id) when is_binary(plan_id) do
    GenServer.call(__MODULE__, {:delete_simulation_plan, plan_id})
  end

  @spec list_simulation_plans() :: %{optional(String.t()) => SimulationPlan.t()}
  def list_simulation_plans do
    GenServer.call(__MODULE__, :list_simulation_plans)
  end

  @spec select_simulation_plan(String.t() | nil) :: :ok
  def select_simulation_plan(nil), do: GenServer.call(__MODULE__, {:select_simulation_plan, nil})

  def select_simulation_plan(plan_id) when is_binary(plan_id) do
    GenServer.call(__MODULE__, {:select_simulation_plan, plan_id})
  end

  @spec get_selected_simulation_plan_id() :: String.t() | nil
  def get_selected_simulation_plan_id do
    GenServer.call(__MODULE__, :get_selected_simulation_plan_id)
  end

  @spec get_selected_simulation_plan() :: SimulationPlan.t() | nil
  def get_selected_simulation_plan do
    GenServer.call(__MODULE__, :get_selected_simulation_plan)
  end

  @spec clear_simulation_plans() :: :ok
  def clear_simulation_plans do
    GenServer.call(__MODULE__, :clear_simulation_plans)
  end

  @spec get_player_ids() :: map()
  def get_player_ids do
    GenServer.call(__MODULE__, :get_player_ids)
  end

  @spec put_player_ids(map()) :: :ok
  def put_player_ids(player_ids) when is_map(player_ids) do
    GenServer.call(__MODULE__, {:put_player_ids, player_ids})
  end

  @spec clear_player_ids() :: :ok
  def clear_player_ids do
    put_player_ids(%{})
  end

  @spec put_userbase_result(boolean(), map() | nil) :: :ok
  def put_userbase_result(userbase_uploaded?, userbase_result)
      when is_boolean(userbase_uploaded?) do
    GenServer.call(__MODULE__, {:put_userbase_result, userbase_uploaded?, userbase_result})
  end

  @spec reset_all() :: :ok
  def reset_all do
    GenServer.call(__MODULE__, :reset_all)
  end

  @impl true
  def init(:ok) do
    {:ok, default_state()}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  def handle_call(:get_db_connection_string, _from, state) do
    {:reply, state.db_connection_string, state}
  end

  def handle_call({:put_db_connection_string, connection_string}, _from, state) do
    {:reply, :ok, %{state | db_connection_string: connection_string}}
  end

  def handle_call({:put_simulation_plan, plan_id, simulation_plan}, _from, state) do
    simulation_plans = Map.put(state.simulation_plans, plan_id, simulation_plan)
    selected_id = state.selected_simulation_plan_id || plan_id

    {:reply, :ok,
     %{state | simulation_plans: simulation_plans, selected_simulation_plan_id: selected_id}}
  end

  def handle_call({:delete_simulation_plan, plan_id}, _from, state) do
    simulation_plans = Map.delete(state.simulation_plans, plan_id)

    selected_id =
      if state.selected_simulation_plan_id == plan_id do
        simulation_plans
        |> Map.keys()
        |> Enum.sort()
        |> List.first()
      else
        state.selected_simulation_plan_id
      end

    {:reply, :ok,
     %{state | simulation_plans: simulation_plans, selected_simulation_plan_id: selected_id}}
  end

  def handle_call(:list_simulation_plans, _from, state) do
    {:reply, state.simulation_plans, state}
  end

  def handle_call({:select_simulation_plan, nil}, _from, state) do
    {:reply, :ok, %{state | selected_simulation_plan_id: nil}}
  end

  def handle_call({:select_simulation_plan, plan_id}, _from, state) do
    selected_id =
      if Map.has_key?(state.simulation_plans, plan_id) do
        plan_id
      else
        state.selected_simulation_plan_id
      end

    {:reply, :ok, %{state | selected_simulation_plan_id: selected_id}}
  end

  def handle_call(:get_selected_simulation_plan_id, _from, state) do
    {:reply, state.selected_simulation_plan_id, state}
  end

  def handle_call(:get_selected_simulation_plan, _from, state) do
    {:reply, Map.get(state.simulation_plans, state.selected_simulation_plan_id), state}
  end

  def handle_call(:clear_simulation_plans, _from, state) do
    {:reply, :ok, %{state | simulation_plans: %{}, selected_simulation_plan_id: nil}}
  end

  def handle_call(:get_player_ids, _from, state) do
    {:reply, state.player_ids, state}
  end

  def handle_call({:put_player_ids, player_ids}, _from, state) do
    {:reply, :ok, %{state | player_ids: player_ids}}
  end

  def handle_call({:put_userbase_result, userbase_uploaded?, userbase_result}, _from, state) do
    {:reply, :ok,
     %{state | userbase_uploaded?: userbase_uploaded?, userbase_result: userbase_result}}
  end

  def handle_call(:reset_all, _from, _state) do
    {:reply, :ok, default_state()}
  end

  defp default_state do
    %{
      db_connection_string: System.get_env("DATABASE_URL") || @default_connection_string,
      simulation_plans: %{},
      selected_simulation_plan_id: nil,
      player_ids: %{},
      userbase_uploaded?: false,
      userbase_result: nil
    }
  end
end
