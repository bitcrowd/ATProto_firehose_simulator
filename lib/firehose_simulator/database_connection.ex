defmodule FirehoseSimulator.DatabaseConnection do
  @moduledoc false

  @default_connection_string "postgres://postgres:postgres@localhost:5432/dataplane"

  @enforce_keys [:connection_string]
  defstruct [:connection_string]

  @type t :: %__MODULE__{
          connection_string: String.t()
        }

  @spec default() :: t()
  def default do
    %__MODULE__{
      connection_string: System.get_env("DATABASE_URL") || @default_connection_string
    }
  end
end
