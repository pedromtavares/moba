defmodule Moba.RankingCacheTest do
  use Moba.DataCase

  @ranking_keys ~w(pve_ranking pve_ranking_available daily_ranking season_ranking)

  setup do
    for key <- @ranking_keys, do: Cachex.del(:game_cache, key)

    on_exit(fn ->
      for key <- @ranking_keys, do: Cachex.del(:game_cache, key)
    end)

    :ok
  end

  test "ranking cache misses are reused without repeating SQL queries" do
    hero = create_base_hero(%{finished_at: Timex.now(), pve_ranking: 1})
    Game.update_player!(hero.player, %{season_ranking: 1, ranking: 1})

    for fetch <- [&Moba.pve_ranking/0, &Moba.pve_ranking_available/0, &Moba.daily_ranking/0, &Moba.season_ranking/0] do
      {first, cold_queries} = count_queries(fetch)
      {second, warm_queries} = count_queries(fetch)
      assert second == first
      assert cold_queries > 0
      assert warm_queries == 0
    end
  end

  test "season ranking picks one best hero per player with a fixed number of queries" do
    first = create_player!(%{season_ranking: 1})
    ranked = create_base_hero(%{pve_ranking: 2, total_gold_farm: 100}, first)
    create_base_hero(%{total_gold_farm: 50_000}, first)
    second = create_player!(%{season_ranking: 2})
    create_base_hero(%{total_gold_farm: 100}, second)
    highest_farm = create_base_hero(%{total_gold_farm: 200}, second)
    no_hero = create_player!(%{season_ranking: 3})

    {players, queries} = count_queries(fn -> Game.season_ranking(50) end)
    players = Map.new(players, &{&1.id, &1})
    assert players[first.id].top_hero.id == ranked.id
    assert players[second.id].top_hero.id == highest_farm.id
    assert is_nil(players[no_hero.id].top_hero)
    assert queries <= 5
    assert Ecto.assoc_loaded?(players[first.id].top_hero.avatar)
    assert Ecto.assoc_loaded?(players[first.id].top_hero.skin)
  end

  defp count_queries(fun) do
    owner = self()
    ref = make_ref()
    :telemetry.attach(ref, [:moba, :repo, :query], fn _, _, _, _ -> send(owner, {:query, ref}) end, nil)

    try do
      result = fun.()
      {result, query_count(ref)}
    after
      :telemetry.detach(ref)
    end
  end

  defp query_count(ref) do
    receive do
      {:query, ^ref} -> 1 + query_count(ref)
    after
      0 -> 0
    end
  end
end
