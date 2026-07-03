defmodule FirehoseSimulator.Scenario.Params.SessionTier do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          max_followers: pos_integer(),
          session_minutes: pos_integer()
        }

  @primary_key false
  embedded_schema do
    field(:max_followers, :integer)
    field(:session_minutes, :integer)
  end

  def changeset(tier, attrs) do
    tier
    |> cast(attrs, [:max_followers, :session_minutes])
    |> validate_required([:max_followers, :session_minutes])
    |> validate_number(:max_followers, greater_than: 0)
    |> validate_number(:session_minutes, greater_than: 0)
  end
end
