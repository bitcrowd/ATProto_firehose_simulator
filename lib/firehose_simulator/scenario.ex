defmodule FirehoseSimulator.Scenario do
  @moduledoc false

  require Logger

  use Ecto.Schema

  alias FirehoseSimulator.Scenario.Follows
  alias FirehoseSimulator.Scenario.JSON
  alias FirehoseSimulator.Scenario.Params.ScenarioParams
  alias FirehoseSimulator.Scenario.Posts
  alias FirehoseSimulator.Scenario.Sessions

  @default_time_unit_duration_ms 86_400_000
  @default_request_interval_ms 30_000
  @default_timeline_limit 20

  @primary_key false
  embedded_schema do
    field(:posts, {:array, :map})
    field(:sessions, {:array, :map})
    field(:follows, {:array, :map})
    field(:request_interval_ms, :integer, default: @default_request_interval_ms)
    field(:timeline_limit, :integer, default: @default_timeline_limit)
    field(:source_path, :string, virtual: true)
  end

  @type t :: %__MODULE__{
          posts: Posts.t() | nil,
          sessions: Sessions.t() | nil,
          follows: Follows.t() | nil,
          request_interval_ms: pos_integer(),
          timeline_limit: pos_integer(),
          source_path: String.t() | nil
        }

  @spec generate_from_json(String.t()) :: {:ok, t()} | {:error, String.t()}
  def generate_from_json(path) when is_binary(path) do
    generate_from_json(scenario_params: path)
  end

  @spec generate_from_json(keyword(String.t())) :: {:ok, t()} | {:error, String.t()}
  def generate_from_json(opts) when is_list(opts) do
    with {:ok, params_path} <- scenario_params_path(opts),
         {:ok, params} <- load_scenario_params(params_path) do
      build_scenario(params)
    end
  end

  @spec generate_from_json_string(String.t()) :: {:ok, t()} | {:error, String.t()}
  def generate_from_json_string(json) when is_binary(json) do
    with {:ok, params} <- load_scenario_params_json(json) do
      build_scenario(params)
    end
  end

  @spec from_json(String.t()) :: {:ok, t()} | {:error, String.t()}
  def from_json(json) when is_binary(json) do
    JSON.decode(json)
  end

  @spec from_json_file(String.t()) :: {:ok, t()} | {:error, String.t()}
  def from_json_file(path) when is_binary(path) do
    Logger.info("loading scenario json file: #{path}")

    :telemetry.execute(
      [:firehose_simulator, :json, :file, :loaded],
      %{count: 1},
      %{path: path, kind: "scenario"}
    )

    with {:ok, json} <- File.read(path),
         {:ok, scenario} <- from_json(json) do
      {:ok, %{scenario | source_path: path}}
    else
      {:error, :enoent} -> {:error, "cannot read scenario json at #{path}"}
      {:error, reason} when is_binary(reason) -> {:error, reason}
      {:error, reason} -> {:error, "failed to load scenario json: #{inspect(reason)}"}
    end
  end

  @spec to_json(t()) :: {:ok, Scenario.t()} | {:error, String.t()}
  def to_json(%__MODULE__{} = scenario) do
    JSON.encode(scenario)
  end

  @spec shift(t(), integer()) :: t()
  def shift(%__MODULE__{} = scenario, offset_ms) when is_integer(offset_ms) do
    %__MODULE__{
      posts: shift_events(scenario.posts, offset_ms),
      sessions: shift_events(scenario.sessions, offset_ms),
      follows: shift_events(scenario.follows, offset_ms),
      request_interval_ms: scenario.request_interval_ms,
      timeline_limit: scenario.timeline_limit,
      source_path: scenario.source_path
    }
  end

  defp load_scenario_params(path) when is_binary(path) do
    Logger.info("loading scenario params json file: #{path}")

    :telemetry.execute(
      [:firehose_simulator, :json, :file, :loaded],
      %{count: 1},
      %{path: path, kind: "scenario_params"}
    )

    case ScenarioParams.load_file(path) do
      {:ok, params} -> {:ok, params}
      {:error, _reason} = error -> error
    end
  end

  defp load_scenario_params(_path),
    do: {:error, "scenario_params path must be a string"}

  defp load_scenario_params_json(json) when is_binary(json) do
    case ScenarioParams.load(json) do
      {:ok, params} -> {:ok, params}
      {:error, _reason} = error -> error
    end
  end

  defp scenario_params_path(opts) when is_list(opts) do
    case Keyword.get(opts, :scenario_params) do
      path when is_binary(path) -> {:ok, path}
      _other -> {:error, "scenario_params path is required"}
    end
  end

  defp build_posts(
         %ScenarioParams{posts_params: nil},
         _seed,
         _time_units,
         _time_unit_duration_ms
       ),
       do: {:ok, nil}

  defp build_posts(
         %ScenarioParams{posts_params: posts_params},
         seed,
         time_units,
         time_unit_duration_ms
       ) do
    {:ok, Posts.generate(posts_params, seed, time_units, time_unit_duration_ms)}
  end

  defp build_sessions(
         %ScenarioParams{sessions_params: nil},
         _seed,
         _time_units,
         _time_unit_duration_ms
       ),
       do: {:ok, nil}

  defp build_sessions(
         %ScenarioParams{sessions_params: sessions_params},
         seed,
         time_units,
         time_unit_duration_ms
       ) do
    {:ok, Sessions.generate(sessions_params, seed, time_units, time_unit_duration_ms)}
  end

  defp build_follows(
         %ScenarioParams{follows_params: nil},
         _seed,
         _time_units,
         _time_unit_duration_ms
       ),
       do: {:ok, nil}

  defp build_follows(
         %ScenarioParams{follows_params: follows_params},
         seed,
         time_units,
         time_unit_duration_ms
       ) do
    {:ok, Follows.generate(follows_params, seed, time_units, time_unit_duration_ms)}
  end

  defp build_scenario(%ScenarioParams{} = params) do
    seed = seed(params)
    time_units = time_units(params)
    unit_duration_ms = time_unit_duration_ms(params)
    request_interval_ms = request_interval_ms(params)
    timeline_limit = timeline_limit(params)

    with {:ok, posts} <- build_posts(params, seed, time_units, unit_duration_ms),
         {:ok, sessions} <- build_sessions(params, seed, time_units, unit_duration_ms),
         {:ok, follows} <- build_follows(params, seed, time_units, unit_duration_ms) do
      {:ok,
       %__MODULE__{
         posts: posts,
         sessions: sessions,
         follows: follows,
         request_interval_ms: request_interval_ms,
         timeline_limit: timeline_limit,
         source_path: nil
       }}
    end
  end

  defp seed(%ScenarioParams{seed: seed}), do: seed

  defp time_units(%ScenarioParams{time_units: time_units}), do: time_units

  defp time_unit_duration_ms(%ScenarioParams{time_unit_duration_ms: nil}),
    do: @default_time_unit_duration_ms

  defp time_unit_duration_ms(%ScenarioParams{time_unit_duration_ms: value}), do: value

  defp request_interval_ms(%ScenarioParams{sessions_params: nil}),
    do: @default_request_interval_ms

  defp request_interval_ms(%ScenarioParams{
         sessions_params: %{request_interval_ms: nil}
       }),
       do: @default_request_interval_ms

  defp request_interval_ms(%ScenarioParams{
         sessions_params: %{request_interval_ms: request_interval_ms}
       }),
       do: request_interval_ms

  defp timeline_limit(%ScenarioParams{sessions_params: nil}),
    do: @default_timeline_limit

  defp timeline_limit(%ScenarioParams{
         sessions_params: %{timeline_limit: nil}
       }),
       do: @default_timeline_limit

  defp timeline_limit(%ScenarioParams{
         sessions_params: %{timeline_limit: timeline_limit}
       }),
       do: timeline_limit

  defp shift_events(nil, _offset_ms), do: nil

  defp shift_events(events, offset_ms) when is_list(events) do
    Enum.map(events, fn event ->
      Map.update!(event, :offset_ms, &(&1 + offset_ms))
    end)
  end
end
