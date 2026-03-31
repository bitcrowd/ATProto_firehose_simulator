defmodule FirehoseSimulator.DatabaseConnection do
  @moduledoc false

  @enforce_keys [:connection_string]
  defstruct [:connection_string]

  @type t :: %__MODULE__{
          connection_string: String.t()
        }
end
