defmodule FirehoseSimulator.SimulationPlan.PostsTest do
  use ExUnit.Case, async: false

  alias FirehoseSimulator.SimulationPlan.Posts
  alias FirehoseSimulator.SimulationPlan.Params.PostsParams
  alias FirehoseSimulator.SimulationPlan.CSV
  alias FirehoseSimulator.SimulationPlan

  @config %PostsParams{
    n: 100,
    max_active_user_id: 2,
    seed: 42,
    time_units: 1,
    tiers: [
      %FirehoseSimulator.SimulationPlan.Params.PostTier{max_followers: 1_000, posts_per_day: 1.0}
    ]
  }

  test "generate/1 returns an in-memory posts list" do
    posts = Posts.generate(@config)

    assert length(posts) == 2
    assert Enum.all?(posts, &is_integer(&1.offset_ms))
    assert posts |> Enum.map(& &1.user_id) |> Enum.sort() == [1, 2]
  end

  @tag :tmp_dir
  test "CSV.write/2 and CSV.load/2 round-trip the generated posts", %{tmp_dir: tmp_dir} do
    posts = Posts.generate(@config)
    simulation_plan = %SimulationPlan{posts: posts, sessions: nil, follows: nil}
    path = Path.join(tmp_dir, "posts.csv")

    assert :ok = CSV.write(simulation_plan, posts: path)

    assert File.read!(path) ==
             "offset_ms,user_id\n" <>
               Enum.map_join(posts, "", fn post ->
                 "#{post.offset_ms},#{post.user_id}\n"
               end)

    assert {:ok, loaded_posts} = CSV.load(:posts, path)
    assert loaded_posts == posts
  end

  test "CSV.load/2 returns an error for missing csv" do
    path = "does-not-exist-posts.csv"
    error_msg = "cannot read posts csv at #{path}"

    assert {:error, ^error_msg} = CSV.load(:posts, path)
  end

  @tag :tmp_dir
  test "CSV.write/2 writes only requested sections", %{tmp_dir: tmp_dir} do
    simulation_plan = %SimulationPlan{
      posts: [%{offset_ms: 10, user_id: 1}],
      sessions: [%{offset_ms: 20, user_id: 2, duration_ms: 60_000}],
      follows: nil
    }

    posts_path = Path.join(tmp_dir, "posts.csv")
    sessions_path = Path.join(tmp_dir, "sessions.csv")
    follows_path = Path.join(tmp_dir, "follows.csv")

    assert :ok = CSV.write(simulation_plan, posts: posts_path, sessions: sessions_path)
    assert File.exists?(posts_path)
    assert File.exists?(sessions_path)
    refute File.exists?(follows_path)
  end
end
