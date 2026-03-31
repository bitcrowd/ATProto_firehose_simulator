defmodule FirehoseSimulator.FollowsTest do
  use ExUnit.Case, async: false

  alias FirehoseSimulator.Follows

  describe "load/1" do
    test "returns a follows struct for valid json" do
      assert {:ok, %Follows{} = follows} =
               Follows.load("""
               {
                 "n": 1000000,
                 "max_active_user_id": 5000,
                 "seed": 42,
                 "time_units": 1,
                 "path": "follows.csv",
                 "tiers": [
                   {"max_followers": 1000, "follows_per_day": 0.25},
                   {"max_followers": 10000, "follows_per_day": 10},
                   {"max_followers": 1000000, "follows_per_day": 3}
                 ]
               }
               """)

      assert follows.path == "follows.csv"
      assert Enum.map(follows.tiers, & &1.follows_per_day) == [0.25, 10.0, 3.0]
    end

    test "returns an error for malformed json" do
      error_msg = "invalid follows json"

      assert {:error, ^error_msg} = Follows.load("{bad json")
    end

    test "requires at least one tier" do
      assert {:error, message} =
               Follows.load("""
               {
                 "n": 1000000,
                 "max_active_user_id": 5000,
                 "seed": 42,
                 "time_units": 1,
                 "path": "follows.csv",
                 "tiers": []
               }
               """)

      assert String.contains?(message, "invalid follows config:")
      assert String.contains?(message, "tiers")
    end
  end

  describe "load!/1" do
    test "returns the follows config on success" do
      assert %Follows{path: "follows.csv"} =
               Follows.load!("""
               {
                 "n": 10,
                 "max_active_user_id": 5,
                 "seed": 1,
                 "time_units": 1,
                 "path": "follows.csv",
                 "tiers": [
                   {"max_followers": 1000, "follows_per_day": 0.25}
                 ]
               }
               """)
    end
  end

  describe "load_file/1" do
    @tag :tmp_dir
    test "reads follows json from disk", %{tmp_dir: tmp_dir} do
      path =
        write_file!(
          tmp_dir,
          "follows",
          """
          {
            "n": 10,
            "max_active_user_id": 5,
            "seed": 1,
            "time_units": 1,
            "path": "follows.csv",
            "tiers": [
              {"max_followers": 1000, "follows_per_day": 0.25}
            ]
          }
          """
        )

      assert {:ok, %Follows{path: "follows.csv"}} = Follows.load_file(path)
    end

    test "returns an error with file path when file does not exist" do
      path = "missing-follows.json"
      error_msg = "cannot read follows file at #{path}"

      assert {:error, ^error_msg} = Follows.load_file(path)
    end
  end

  defp write_file!(tmp_dir, prefix, content) do
    path = Path.join(tmp_dir, "#{prefix}-#{System.unique_integer([:positive])}.json")
    File.write!(path, content)
    path
  end
end
