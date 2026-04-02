defmodule FirehoseSimulatorTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias FirehoseSimulator.DatabaseConnection
  alias FirehoseSimulator.Player
  alias FirehoseSimulator.SimulationPlan

  describe "load_simulation_plan_from_json/1" do
    @tag :tmp_dir
    test "loads simulation plan json files through the top-level api", %{tmp_dir: tmp_dir} do
      posts_path =
        write_file!(
          tmp_dir,
          "posts",
          """
          {
            "n": 10,
            "max_active_user_id": 5,
            "seed": 1,
            "time_units": 1,
            "tiers": [
              {"max_followers": 1000, "posts_per_day": 0.25}
            ]
          }
          """
        )

      capture_log(fn ->
        send(
          self(),
          {:result, FirehoseSimulator.load_simulation_plan_from_json(posts: posts_path)}
        )
      end)

      assert_receive {:result, {:ok, %SimulationPlan{posts_plan: posts_plan}}}
      assert is_list(posts_plan.posts)
    end
  end

  describe "play/2" do
    setup do
      on_exit(fn ->
        _ = Player.stop()
      end)

      :ok
    end

    test "starts playing immediately with an in-memory simulation plan" do
      simulation_plan = %SimulationPlan{sessions_plan: nil, posts_plan: nil, follows_plan: nil}

      capture_log(fn ->
        assert {:ok, %{started?: true}} =
                 FirehoseSimulator.play(simulation_plan, scheduler_count: 1)
      end)

      # Ensure EventFeeder has processed the start cast.
      _ = :sys.get_state(FirehoseSimulator.SimulationPlan.EventFeeder)

      status = Player.status()
      assert status.running?
      assert status.loaded?
      assert status.feeder.started?
    end
  end

  describe "create_userbase/2" do
    test "returns file load errors before attempting database work" do
      connection = %DatabaseConnection{connection_string: "postgres://example"}

      capture_log(fn ->
        assert {:error, "cannot read userbase file at missing-userbase.json"} =
                 FirehoseSimulator.create_userbase("missing-userbase.json", connection)
      end)
    end
  end

  defp write_file!(tmp_dir, prefix, content) do
    path = Path.join(tmp_dir, "#{prefix}-#{System.unique_integer([:positive])}.json")
    File.write!(path, content)
    path
  end
end
