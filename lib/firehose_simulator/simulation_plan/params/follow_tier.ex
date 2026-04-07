defmodule FirehoseSimulator.SimulationPlan.Params.FollowTier do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{
          max_followers: pos_integer(),
          follows_per_time_unit: float()
        }

  @primary_key false
  embedded_schema do
    field(:max_followers, :integer)
    field(:follows_per_time_unit, :float)
  end

  def changeset(tier, attrs) do
    tier
    |> cast(attrs, [:max_followers, :follows_per_time_unit])
    |> validate_required([:max_followers, :follows_per_time_unit])
    |> validate_number(:max_followers, greater_than: 0)
    |> validate_number(:follows_per_time_unit, greater_than_or_equal_to: 0)
  end
end
