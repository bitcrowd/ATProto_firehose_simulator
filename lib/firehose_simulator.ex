defmodule FirehoseSimulator do
  @moduledoc """
  FirehoseSimulator keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  require Logger

  alias FirehoseSimulator.BulkCreation
  alias FirehoseSimulator.DatabaseConnection
  alias FirehoseSimulator.SimulationPlan.Userbase

  @default_userbase_filename "userbase.json"
  @default_connection_string "postgres://postgres:postgres@localhost:5432/atproto_blacksky?options=-csearch_path%3Dbsky"

  @spec create_userbase() :: {:ok, map()} | {:error, String.t()}
  def create_userbase do
    create_userbase(userbase_filename(), database_connection())
  end

  @spec create_userbase(String.t(), DatabaseConnection.t()) :: {:ok, map()} | {:error, String.t()}
  def create_userbase(path, %DatabaseConnection{} = connection) when is_binary(path) do
    with {:ok, userbase} <- load_userbase(path),
         {:ok, result} <- do_create_userbase(userbase, connection) do
      {:ok, result}
    end
  end

  defp userbase_filename do
    System.get_env("USERBASE_JSON", @default_userbase_filename)
  end

  defp database_connection do
    %DatabaseConnection{
      connection_string: System.get_env("DATABASE_URL") || @default_connection_string
    }
  end

  defp load_userbase(path) do
    Logger.info("loading userbase from #{path}")

    case(Userbase.load_file(path)) do
      {:ok, userbase} ->
        Logger.info(
          "loaded userbase #{userbase.name} from #{path} with #{userbase.num_users} users"
        )

        {:ok, userbase}

      {:error, reason} ->
        Logger.error("failed to load userbase from #{path}: #{reason}")
        {:error, reason}
    end
  end

  defp do_create_userbase(userbase, connection) do
    Logger.info("creating userbase #{userbase.name} in database for #{userbase.num_users} users")

    case BulkCreation.create_userbase(userbase, connection) do
      {:ok, result} ->
        Logger.info("created userbase \"#{userbase.name}\": #{inspect(result)}")
        {:ok, result}

      {:error, reason} ->
        Logger.error("failed to create userbase #{userbase.name}: #{reason}")
        {:error, reason}
    end
  end
end
