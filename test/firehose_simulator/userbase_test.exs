defmodule FirehoseSimulator.UserbaseTest do
  use ExUnit.Case, async: false

  alias FirehoseSimulator.Userbase

  describe "load/1" do
    test "returns a userbase struct for valid json" do
      assert {:ok,
              %Userbase{
                name: "not yet twitter",
                num_users: 1_000_000,
                max_active_user_id: 25_000,
                follower_density: 5.0
              }} =
               Userbase.load("""
               {
                 "name": "not yet twitter",
                 "num_users": 1000000,
                 "max_active_user_id": 25000,
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
                 "name": "not yet twitter",
                 "num_users": 1000000
               }
               """)

      assert String.contains?(message, "invalid userbase config:")
      assert String.contains?(message, "max_active_user_id")
      assert String.contains?(message, "follower_density")
    end

    test "returns invalid field details for range errors" do
      assert {:error, message} =
               Userbase.load("""
               {
                 "name": "not yet twitter",
                 "num_users": 100,
                 "max_active_user_id": 101,
                 "follower_density": 1.5
               }
               """)

      assert String.contains?(message, "invalid userbase config:")
      assert String.contains?(message, "max_active_user_id")
      assert String.contains?(message, "less than or equal to num_users")
    end

    test "ignores unknown keys" do
      assert {:ok, %Userbase{name: "with extras"}} =
               Userbase.load("""
               {
                 "name": "with extras",
                 "num_users": 100,
                 "max_active_user_id": 20,
                 "follower_density": 0.0,
                 "unknown_key": "ignored"
               }
               """)
    end
  end

  describe "load!/1" do
    test "returns the userbase on success" do
      assert %Userbase{
               name: "bang",
               num_users: 100,
               max_active_user_id: 10,
               follower_density: 2.0
             } =
               Userbase.load!("""
               {
                 "name": "bang",
                 "num_users": 100,
                 "max_active_user_id": 10,
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
    @tag :tmp_dir
    test "reads userbase json from disk", %{tmp_dir: tmp_dir} do
      path =
        write_file!(
          tmp_dir,
          """
          {
            "name": "from file",
            "num_users": 100,
            "max_active_user_id": 10,
            "follower_density": 2.0
          }
          """
        )

      assert {:ok, %Userbase{name: "from file"}} = Userbase.load_file(path)
    end

    test "returns an error with file path when file does not exist" do
      path = "does-not-exist.json"
      error_msg = "cannot read userbase file at #{path}"

      assert {:error, ^error_msg} = Userbase.load_file(path)
    end
  end

  defp write_file!(tmp_dir, content) do
    path = Path.join(tmp_dir, "userbase-#{System.unique_integer([:positive])}.json")
    File.write!(path, content)
    path
  end
end
