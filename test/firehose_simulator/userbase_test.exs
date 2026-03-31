defmodule FirehoseSimulator.UserbaseTest do
  use ExUnit.Case, async: false

  alias FirehoseSimulator.Userbase

  describe "load/1" do
    @tag :tmp_dir
    test "returns a userbase struct for valid json", %{tmp_dir: tmp_dir} do
      path =
        write_file!(
          tmp_dir,
          """
          {
            "name": "not yet twitter",
            "num_users": 1000000,
            "max_active_user_id": 25000,
            "follower_density": 5.0
          }
          """
        )

      assert {:ok,
              %Userbase{
                name: "not yet twitter",
                num_users: 1_000_000,
                max_active_user_id: 25_000,
                follower_density: 5.0
              }} = Userbase.load(path)
    end

    test "returns an error with file path when file does not exist" do
      path = "does-not-exist.json"
      error_msg = "cannot read userbase file at #{path}"

      assert {:error, ^error_msg} = Userbase.load(path)
    end

    @tag :tmp_dir
    test "returns an error with file path for malformed json", %{tmp_dir: tmp_dir} do
      path = write_file!(tmp_dir, "{bad json")
      error_msg = "invalid userbase json at #{path}"

      assert {:error, ^error_msg} = Userbase.load(path)
    end

    @tag :tmp_dir
    test "returns missing fields for required fields validation", %{tmp_dir: tmp_dir} do
      path =
        write_file!(
          tmp_dir,
          """
          {
            "name": "not yet twitter",
            "num_users": 1000000
          }
          """
        )

      assert {:error, message} = Userbase.load(path)
      assert String.contains?(message, "invalid userbase config at #{path}:")
      assert String.contains?(message, "max_active_user_id")
      assert String.contains?(message, "follower_density")
    end

    @tag :tmp_dir
    test "returns invalid field details for range errors", %{tmp_dir: tmp_dir} do
      path =
        write_file!(
          tmp_dir,
          """
          {
            "name": "not yet twitter",
            "num_users": 100,
            "max_active_user_id": 101,
            "follower_density": 1.5
          }
          """
        )

      assert {:error, message} = Userbase.load(path)
      assert String.contains?(message, "invalid userbase config at #{path}:")
      assert String.contains?(message, "max_active_user_id")
      assert String.contains?(message, "less than or equal to num_users")
    end

    @tag :tmp_dir
    test "ignores unknown keys", %{tmp_dir: tmp_dir} do
      path =
        write_file!(
          tmp_dir,
          """
          {
            "name": "with extras",
            "num_users": 100,
            "max_active_user_id": 20,
            "follower_density": 0.0,
            "unknown_key": "ignored"
          }
          """
        )

      assert {:ok, %Userbase{name: "with extras"}} = Userbase.load(path)
    end
  end

  describe "load!/1" do
    @tag :tmp_dir
    test "returns the userbase on success", %{tmp_dir: tmp_dir} do
      path =
        write_file!(
          tmp_dir,
          """
          {
            "name": "bang",
            "num_users": 100,
            "max_active_user_id": 10,
            "follower_density": 2.0
          }
          """
        )

      assert %Userbase{
               name: "bang",
               num_users: 100,
               max_active_user_id: 10,
               follower_density: 2.0
             } = Userbase.load!(path)
    end

    test "raises with an error that includes file path" do
      path = "missing-file.json"
      error_msg = "cannot read userbase file at #{path}"

      assert_raise RuntimeError, error_msg, fn ->
        Userbase.load!(path)
      end
    end
  end

  defp write_file!(tmp_dir, content) do
    path = Path.join(tmp_dir, "userbase-#{System.unique_integer([:positive])}.json")
    File.write!(path, content)
    path
  end
end
