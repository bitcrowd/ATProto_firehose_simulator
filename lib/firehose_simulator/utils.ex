defmodule FirehoseSimulator.Utils do
  @moduledoc false
  def slugify(value, fallback \\ "") do
    value
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_-]+/u, "-")
    |> String.trim("-")
    |> case do
      "" -> fallback
      slug -> slug
    end
  end
end
