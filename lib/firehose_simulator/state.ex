defmodule FirehoseSimulator.State do
  @moduledoc false

  use GenServer

  alias FirehoseSimulator.Scenario
  alias FirehoseSimulator.SimulationPlan

  @type state :: %{
          scenarios: %{optional(String.t()) => Scenario.t()},
          selected_scenario_id: String.t() | nil,
          simulation_plan: SimulationPlan.t(),
          running_players: %{optional(String.t()) => map()},
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

  @spec put_scenario(String.t(), Scenario.t()) :: :ok
  def put_scenario(scenario_id, %Scenario{} = scenario) when is_binary(scenario_id) do
    GenServer.call(__MODULE__, {:put_scenario, scenario_id, scenario})
  end

  @spec delete_scenario(String.t()) :: :ok
  def delete_scenario(scenario_id) when is_binary(scenario_id) do
    GenServer.call(__MODULE__, {:delete_scenario, scenario_id})
  end

  @spec list_scenarios() :: %{optional(String.t()) => Scenario.t()}
  def list_scenarios do
    GenServer.call(__MODULE__, :list_scenarios)
  end

  @spec select_scenario(String.t() | nil) :: :ok
  def select_scenario(nil), do: GenServer.call(__MODULE__, {:select_scenario, nil})

  def select_scenario(scenario_id) when is_binary(scenario_id) do
    GenServer.call(__MODULE__, {:select_scenario, scenario_id})
  end

  @spec get_selected_scenario_id() :: String.t() | nil
  def get_selected_scenario_id do
    GenServer.call(__MODULE__, :get_selected_scenario_id)
  end

  @spec get_selected_scenario() :: Scenario.t() | nil
  def get_selected_scenario do
    GenServer.call(__MODULE__, :get_selected_scenario)
  end

  @spec clear_scenarios() :: :ok
  def clear_scenarios do
    GenServer.call(__MODULE__, :clear_scenarios)
  end

  @spec get_simulation_plan() :: SimulationPlan.t()
  def get_simulation_plan do
    GenServer.call(__MODULE__, :get_simulation_plan)
  end

  def put_simulation_plan(%SimulationPlan{} = simulation_plan) do
    GenServer.call(__MODULE__, {:put_simulation_plan, simulation_plan})
  end

  @spec list_running_players() :: %{optional(String.t()) => map()}
  def list_running_players do
    GenServer.call(__MODULE__, :list_running_players)
  end

  @spec put_running_player(String.t(), map()) :: :ok
  def put_running_player(player_id, metadata) when is_binary(player_id) and is_map(metadata) do
    GenServer.call(__MODULE__, {:put_running_player, player_id, metadata})
  end

  @spec delete_running_player(String.t()) :: :ok
  def delete_running_player(player_id) when is_binary(player_id) do
    GenServer.call(__MODULE__, {:delete_running_player, player_id})
  end

  @spec clear_running_players() :: :ok
  def clear_running_players do
    GenServer.call(__MODULE__, :clear_running_players)
  end

  @spec get_player_ids() :: map()
  def get_player_ids do
    list_running_players()
  end

  @spec put_player_ids(map()) :: :ok
  def put_player_ids(player_ids) when is_map(player_ids) do
    :ok = clear_running_players()

    Enum.each(player_ids, fn {player_id, metadata} ->
      put_running_player(to_string(player_id), normalize_running_player_metadata(metadata))
    end)

    :ok
  end

  @spec clear_player_ids() :: :ok
  def clear_player_ids do
    clear_running_players()
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

  def handle_call({:put_scenario, scenario_id, scenario}, _from, state) do
    scenarios = Map.put(state.scenarios, scenario_id, scenario)
    selected_id = state.selected_scenario_id || scenario_id
    {:reply, :ok, %{state | scenarios: scenarios, selected_scenario_id: selected_id}}
  end

  def handle_call({:delete_scenario, scenario_id}, _from, state) do
    scenarios = Map.delete(state.scenarios, scenario_id)

    selected_id =
      if state.selected_scenario_id == scenario_id do
        scenarios
        |> Map.keys()
        |> Enum.sort()
        |> List.first()
      else
        state.selected_scenario_id
      end

    {:reply, :ok, %{state | scenarios: scenarios, selected_scenario_id: selected_id}}
  end

  def handle_call(:list_scenarios, _from, state) do
    {:reply, state.scenarios, state}
  end

  def handle_call({:select_scenario, nil}, _from, state) do
    {:reply, :ok, %{state | selected_scenario_id: nil}}
  end

  def handle_call({:select_scenario, scenario_id}, _from, state) do
    selected_id =
      if Map.has_key?(state.scenarios, scenario_id) do
        scenario_id
      else
        state.selected_scenario_id
      end

    {:reply, :ok, %{state | selected_scenario_id: selected_id}}
  end

  def handle_call(:get_selected_scenario_id, _from, state) do
    {:reply, state.selected_scenario_id, state}
  end

  def handle_call(:get_selected_scenario, _from, state) do
    {:reply, Map.get(state.scenarios, state.selected_scenario_id), state}
  end

  def handle_call(:clear_scenarios, _from, state) do
    {:reply, :ok, %{state | scenarios: %{}, selected_scenario_id: nil}}
  end

  def handle_call(:get_simulation_plan, _from, state) do
    {:reply, state.simulation_plan, state}
  end

  def handle_call({:put_simulation_plan, simulation_plan}, _from, state) do
    {:reply, :ok, %{state | simulation_plan: simulation_plan}}
  end

  def handle_call(:list_running_players, _from, state) do
    {:reply, state.running_players, state}
  end

  def handle_call({:put_running_player, player_id, metadata}, _from, state) do
    running_players = Map.put(state.running_players, player_id, metadata)
    {:reply, :ok, %{state | running_players: running_players}}
  end

  def handle_call({:delete_running_player, player_id}, _from, state) do
    running_players = Map.delete(state.running_players, player_id)
    {:reply, :ok, %{state | running_players: running_players}}
  end

  def handle_call(:clear_running_players, _from, state) do
    {:reply, :ok, %{state | running_players: %{}}}
  end

  def handle_call({:put_userbase_result, userbase_uploaded?, userbase_result}, _from, state) do
    {:reply, :ok,
     %{state | userbase_uploaded?: userbase_uploaded?, userbase_result: userbase_result}}
  end

  def handle_call(:reset_all, _from, _state) do
    {:reply, :ok, default_state()}
  end

  defp default_state do
    {:ok, simulation_plan} = SimulationPlan.new(%{entries: []})

    %{
      scenarios: %{},
      selected_scenario_id: nil,
      simulation_plan: simulation_plan,
      running_players: %{},
      userbase_uploaded?: false,
      userbase_result: nil
    }
  end

  defp normalize_running_player_metadata(metadata) when is_map(metadata), do: metadata
  defp normalize_running_player_metadata(metadata), do: %{value: metadata}
end
