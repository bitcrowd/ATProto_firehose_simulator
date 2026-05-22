defmodule FirehoseSimulator.BaseData.UserbaseTest do
  use ExUnit.Case, async: false

  alias FirehoseSimulator.BaseData.Userbase

  describe "load/1" do
    test "returns a userbase struct for valid json" do
      assert {:ok,
              %Userbase{
                name: "not yet twitter",
                num_users: 1_000_000,
                follower_density: 5.0
              }} =
               Userbase.load("""
               {
                 "name": "not yet twitter",
                 "num_users": 1000000,
                 "follower_density": 5.0
               }
               """)
    end

    test "returns an error for malformed json" do
      error_msg = "invalid userbase json"

      assert {:error, ^error_msg} = Userbase.load("{bad json")
    end

    test "returns missing fields for required fields validation" do
      assert {:error, message} =
               Userbase.load("""
               {
                 "num_users": 1000000
               }
               """)

      assert String.contains?(message, "invalid userbase config:")
      assert String.contains?(message, "name")
    end

    test "returns invalid field details for range errors" do
      assert {:error, message} =
               Userbase.load("""
               {
                 "name": "not yet twitter",
                 "num_users": 0,
                 "follower_density": 1.5
               }
               """)

      assert String.contains?(message, "invalid userbase config:")
      assert String.contains?(message, "num_users")
      assert String.contains?(message, "must be greater than 0")
    end

    test "ignores unknown keys" do
      assert {:ok, %Userbase{name: "with extras"}} =
               Userbase.load("""
               {
                 "name": "with extras",
                 "num_users": 100,
                 "max_active_user_id": 20,
                 "follower_density": 1.0,
                 "unknown_key": "ignored"
               }
               """)
    end

    test "defaults follower_density to 1.0 when omitted" do
      assert {:ok, %Userbase{} = userbase} =
               Userbase.load("""
               {
                 "name": "with default density",
                 "num_users": 100
               }
               """)

      assert userbase.follower_density == 1.0
    end
  end

  describe "load!/1" do
    test "returns the userbase on success" do
      assert %Userbase{
               name: "bang",
               num_users: 100,
               follower_density: 2.0
             } =
               Userbase.load!("""
               {
                 "name": "bang",
                 "num_users": 100,
                 "follower_density": 2.0
               }
               """)
    end

    test "raises with a parse error" do
      error_msg = "invalid userbase json"

      assert_raise RuntimeError, error_msg, fn ->
        Userbase.load!("{bad json")
      end
    end
  end

  describe "load_file/1" do
    test "returns an error with file path when file does not exist" do
      path = "does-not-exist.json"
      error_msg = "cannot read userbase file at #{path}"

      assert {:error, ^error_msg} = Userbase.load_file(path)
    end
  end
end
