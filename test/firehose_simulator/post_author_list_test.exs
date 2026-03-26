defmodule FirehoseSimulator.PostAuthorListTest do
  use ExUnit.Case, async: true

  alias FirehoseSimulator.PostAuthorList

  test "generates a sequential user id list" do
    assert {:ok, [1, 2, 3, 4]} = PostAuthorList.generate(4)
  end

  test "supports custom starting ids" do
    assert {:ok, [10, 11, 12]} = PostAuthorList.generate(3, 10)
  end
end
