defmodule Moba.Game.SeasonScoreTest do
  use Moba.DataCase
  alias Moba.Game.{SeasonScore, Query.PlayerQuery}

  test "combines direct Training Rank score, rating, best streak at twenty per day and the current title" do
    player = %Game.Schema.Player{pve_tier: 7, pvp_points: 120, best_immortal_streak: 3, pvp_tier: 2, ranking: 1}
    assert SeasonScore.training_points(player) == 700
    assert SeasonScore.streak_points(player) == 60
    assert SeasonScore.immortal_bonus(player) == 200
    assert Game.season_score(player) == 1080
    assert Game.season_score(%{player | ranking: 2}) == 880
    assert Game.season_score(%{player | pvp_tier: 1}) == 880
  end

  test "SQL standings and displayed scores agree, and the title bonus transfers without removing best-streak points" do
    former = create_player!(%{pve_tier: 0, pvp_points: 0, best_immortal_streak: 20, pvp_tier: 2, ranking: 2})
    invoker = create_player!(%{pve_tier: 7, pvp_points: 0, best_immortal_streak: 0})
    holder = create_player!(%{pve_tier: 5, pvp_points: 0, best_immortal_streak: 1, pvp_tier: 2, ranking: 1})
    ids = Enum.map([former, invoker, holder], & &1.id)
    for player <- [former, invoker, holder], do: Accounts.set_online_now(Accounts.get_user!(player.user_id))
    score = SeasonScore.expression()

    stored =
      Repo.all(from p in Game.Schema.Player, where: p.id in ^ids, select: ^%{id: dynamic([p], p.id), score: score})
      |> Map.new(&{&1.id, &1.score})

    for player <- [former, invoker, holder], do: assert(stored[player.id] == Game.season_score(player))
    ranked = PlayerQuery.season_ranking(1000) |> Repo.all() |> Enum.filter(&(&1.id in ids))
    assert Enum.map(ranked, & &1.id) == [holder.id, invoker.id, former.id]
    Game.update_season_ranking!()
    assert Game.get_player!(holder.id).season_ranking < Game.get_player!(invoker.id).season_ranking
    former = Game.update_player!(former, %{ranking: 1})
    holder = Game.update_player!(holder, %{ranking: 2})
    assert Game.season_score(former) == 600
    assert Game.season_score(holder) == 520
    assert former.best_immortal_streak == 20
    reranked = PlayerQuery.season_ranking(1000) |> Repo.all() |> Enum.filter(&(&1.id in ids))
    assert Enum.map(reranked, & &1.id) == [invoker.id, former.id, holder.id]
  end

  test "return campaign audience uses the same score expression" do
    first = create_player!(%{pve_tier: 7, best_immortal_streak: 2, pvp_points: 10})
    second = create_player!(%{pve_tier: 6, best_immortal_streak: 0, pvp_points: 0, pvp_tier: 2, ranking: 1})
    contacts = Moba.Accounts.ReturnCampaign.audience(user_ids: [first.user_id, second.user_id])
    assert Enum.map(contacts, & &1.player_id) == [second.id, first.id]
    assert Enum.map(contacts, & &1.score) == [800, 750]
  end
end
