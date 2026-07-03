defmodule FirehoseSimulator.Scenario.Params.PostTier do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          max_followers: pos_integer(),
          posts_per_time_unit: float()
        }

  @primary_key false
  embedded_schema do
    field(:max_followers, :integer)
    field(:posts_per_time_unit, :float)
  end

  def changeset(tier, attrs) do
    tier
    |> cast(attrs, [:max_followers, :posts_per_time_unit])
    |> validate_required([:max_followers, :posts_per_time_unit])
    |> validate_number(:max_followers, greater_than: 0)
    |> validate_number(:posts_per_time_unit, greater_than_or_equal_to: 0)
  end
end
