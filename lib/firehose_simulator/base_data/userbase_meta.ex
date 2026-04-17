defmodule FirehoseSimulator.BaseData.UserbaseMeta do
  @enforce_keys [:version, :kind, :run_id, :exported_at, :userbase, :files]
  defstruct [:version, :kind, :run_id, :exported_at, :userbase, :files]

  @type file_info :: %{
          required(:path) => String.t(),
          required(:row_count) => non_neg_integer()
        }

  @type t :: %__MODULE__{
          version: pos_integer(),
          kind: String.t(),
          run_id: String.t(),
          exported_at: String.t(),
          userbase: map(),
          files: %{
            required(:actor) => file_info(),
            required(:follow) => file_info()
          }
        }

  @spec new(keyword()) :: t()
  def new(opts) do
    %__MODULE__{
      version: Keyword.get(opts, :version, 1),
      kind: Keyword.get(opts, :kind, "userbase"),
      run_id: Keyword.fetch!(opts, :run_id),
      exported_at: Keyword.fetch!(opts, :exported_at),
      userbase: Keyword.fetch!(opts, :userbase),
      files: Keyword.fetch!(opts, :files)
    }
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = meta) do
    %{
      "version" => meta.version,
      "kind" => meta.kind,
      "run_id" => meta.run_id,
      "exported_at" => meta.exported_at,
      "userbase" => meta.userbase,
      "files" => %{
        "actor" => file_info_to_map(meta.files.actor),
        "follow" => file_info_to_map(meta.files.follow)
      }
    }
  end

  @spec encode(t()) :: {:ok, String.t()} | {:error, String.t()}
  def encode(%__MODULE__{} = meta) do
    case Jason.encode(to_map(meta), pretty: true) do
      {:ok, json} -> {:ok, json <> "\n"}
      {:error, reason} -> {:error, "failed to encode userbase meta json: #{inspect(reason)}"}
    end
  end

  @spec write_file(t(), String.t()) :: :ok | {:error, String.t()}
  def write_file(%__MODULE__{} = meta, path) when is_binary(path) do
    with :ok <- File.mkdir_p(Path.dirname(path)),
         {:ok, json} <- encode(meta),
         :ok <- File.write(path, json) do
      :ok
    else
      {:error, reason} when is_binary(reason) ->
        {:error, reason}

      {:error, reason} ->
        {:error, "failed to write userbase meta file: #{inspect(reason)}"}
    end
  end

  @spec load(String.t(), keyword()) :: {:ok, t()} | {:error, String.t()}
  def load(json, opts \\ []) when is_binary(json) and is_list(opts) do
    validate_files? = Keyword.get(opts, :validate_files, true)

    with {:ok, decoded} <- decode_json(json),
         {:ok, meta} <- from_map(decoded),
         :ok <- maybe_validate_files(meta, validate_files?) do
      {:ok, meta}
    end
  end

  @spec load_file(String.t(), keyword()) :: {:ok, t()} | {:error, String.t()}
  def load_file(path, opts \\ []) when is_binary(path) and is_list(opts) do
    with {:ok, json} <- read_json_file(path) do
      load(json, opts)
    end
  end

  @spec from_map(map()) :: {:ok, t()} | {:error, String.t()}
  def from_map(%{} = map) do
    with {:ok, version} <- fetch_integer(map, "version", "version"),
         :ok <- validate_version(version),
         {:ok, kind} <- fetch_binary(map, "kind", "kind"),
         :ok <- validate_kind(kind),
         {:ok, run_id} <- fetch_binary(map, "run_id", "run_id"),
         {:ok, exported_at} <- fetch_binary(map, "exported_at", "exported_at"),
         {:ok, userbase} <- fetch_map(map, "userbase", "userbase"),
         {:ok, files} <- fetch_map(map, "files", "files"),
         {:ok, actor} <- fetch_file_info(files, "actor"),
         {:ok, follow} <- fetch_file_info(files, "follow"),
         :ok <- validate_file_path(actor.path, "actor"),
         :ok <- validate_file_path(follow.path, "follow") do
      {:ok,
       %__MODULE__{
         version: version,
         kind: kind,
         run_id: run_id,
         exported_at: exported_at,
         userbase: userbase,
         files: %{actor: actor, follow: follow}
       }}
    end
  end

  def from_map(_), do: {:error, "invalid userbase meta json"}

  defp validate_version(1), do: :ok
  defp validate_version(version), do: {:error, "unsupported userbase meta version: #{version}"}

  defp validate_kind("userbase"), do: :ok
  defp validate_kind(kind), do: {:error, "invalid userbase meta kind: #{inspect(kind)}"}

  defp validate_files(%__MODULE__{} = meta) do
    with :ok <- validate_file_exists(meta.files.actor.path, "actor"),
         :ok <- validate_file_exists(meta.files.follow.path, "follow") do
      :ok
    end
  end

  defp maybe_validate_files(meta, true), do: validate_files(meta)
  defp maybe_validate_files(_meta, false), do: :ok

  defp validate_file_path(path, name) do
    cond do
      Path.type(path) != :absolute ->
        {:error, "#{name} csv path must be absolute"}

      true ->
        :ok
    end
  end

  defp validate_file_exists(path, name) do
    cond do
      not File.regular?(path) ->
        {:error, "#{name} csv file does not exist at #{path}"}

      true ->
        :ok
    end
  end

  defp fetch_file_info(files, key) do
    with {:ok, file_info} <- fetch_map(files, key, "#{key} file"),
         {:ok, path} <- fetch_binary(file_info, "path", "#{key} path"),
         {:ok, row_count} <- fetch_integer(file_info, "row_count", "#{key} row_count") do
      {:ok, %{path: path, row_count: row_count}}
    end
  end

  defp fetch_map(map, key, label) do
    case Map.fetch(map, key) do
      {:ok, %{} = value} -> {:ok, value}
      {:ok, _value} -> {:error, "invalid #{label}"}
      :error -> {:error, "missing #{label}"}
    end
  end

  defp fetch_binary(map, key, label) do
    case Map.fetch(map, key) do
      {:ok, value} when is_binary(value) and value != "" -> {:ok, value}
      {:ok, _value} -> {:error, "invalid #{label}"}
      :error -> {:error, "missing #{label}"}
    end
  end

  defp fetch_integer(map, key, label) do
    case Map.fetch(map, key) do
      {:ok, value} when is_integer(value) and value >= 0 -> {:ok, value}
      {:ok, _value} -> {:error, "invalid #{label}"}
      :error -> {:error, "missing #{label}"}
    end
  end

  defp file_info_to_map(%{path: path, row_count: row_count}) do
    %{"path" => path, "row_count" => row_count}
  end

  defp read_json_file(path) do
    case File.read(path) do
      {:ok, json} -> {:ok, json}
      {:error, _reason} -> {:error, "cannot read userbase meta file at #{path}"}
    end
  end

  defp decode_json(json) do
    case Jason.decode(json) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _reason} -> {:error, "invalid userbase meta json"}
    end
  end
end
