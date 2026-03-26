defmodule FirehoseSimulator.PostAuthorList do
  @moduledoc """
  Generates a deterministic list of user IDs that should create posts.
  """

  @doc """
  Generates `n` user IDs beginning at `start_id`.

  ## Examples

      iex> FirehoseSimulator.PostAuthorList.generate(3)
      {:ok, [1, 2, 3]}

      iex> FirehoseSimulator.PostAuthorList.generate(3, 10)
      {:ok, [10, 11, 12]}
  """
  def generate(n, start_id \\ 1) when is_integer(n) and n >= 1 do
    {:ok, Enum.to_list(start_id..(start_id + n - 1))}
  end
end
