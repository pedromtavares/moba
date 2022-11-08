defmodule Moba.Game.Players do
  @moduledoc """
  Manages Match records and queries.
  See Moba.Game.Schema.Match for more info.
  """

  alias Moba.{Repo, Game}
  alias Game.Schema.Player
  alias Game.Query.PlayerQuery

  def add_total_farm!(%{player: player} = hero) do
    update_player!(player, %{total_farm: player.total_farm + hero.total_gold_farm + hero.total_xp_farm})
  end

  def bot_ranking, do: PlayerQuery.bots() |> PlayerQuery.by_pvp_points() |> Repo.all()

  def create_player!(attrs \\ %{}) do
    %Player{}
    |> Player.changeset(attrs)
    |> Repo.insert!()
  end

  def duel_opponents(player, online_ids) do
    PlayerQuery.non_bots()
    |> PlayerQuery.non_guests()
    |> PlayerQuery.with_status("available")
    |> PlayerQuery.exclude_ids([player.id])
    |> PlayerQuery.with_ids(online_ids)
    |> Repo.all()
    |> Repo.preload(:user)
  end

  @doc """
  Sets pvp_points and the duel_score map that is displayed on the player's profile
  Each player holds the score count of every other player they have dueled against
  """
  def duel_update!(player, updates) do
    loser_id = updates[:loser_id] && Integer.to_string(updates[:loser_id])
    current_score = player.duel_score[loser_id] || 0
    duel_score = loser_id && Map.put(player.duel_score, loser_id, current_score + 1)

    updates = %{
      duel_score: duel_score || player.duel_score,
      pvp_points: updates[:pvp_points] || player.pvp_points
    }

    update_player!(player, updates)
  end

  def get_player!(id), do: PlayerQuery.load() |> Repo.get!(id)

  def get_player_from_user!(user_id), do: Repo.get_by(PlayerQuery.load(), user_id: user_id)

  def matchmaking_opponent(%{pvp_tier: tier, id: id}) do
    PlayerQuery.matchmaking_opponents(id, tier) |> PlayerQuery.limit_by(1) |> Repo.all() |> List.first()
  end

  def pvp_points_for(tier) do
    case tier do
      1 -> 30
      2 -> 60
      3 -> 100
      4 -> 130
      5 -> 160
      6 -> 200
      7 -> 230
      8 -> 260
      9 -> 300
      10 -> 330
      11 -> 360
      12 -> 400
      13 -> 430
      14 -> 460
      15 -> 500
      16 -> 600
      17 -> 750
      18 -> 1000
      _ -> 0
    end
  end

  @doc """
  Lists Players by their ranking
  """
  def pvp_ranking(limit), do: PlayerQuery.ranking(limit) |> Repo.all() |> Repo.preload(:user)

  def set_player_available!(player), do: update_player!(player, %{status: "available"})

  def set_player_unavailable!(player), do: update_player!(player, %{status: "unavailable"})

  def set_current_pve_hero!(player, hero_id), do: update_player!(player, %{current_pve_hero_id: hero_id})

  def update_collection!(player, hero_collection) do
    update_player!(player, %{hero_collection: hero_collection})
  end

  def update_player!(%Player{} = player, attrs) do
    player
    |> Player.changeset(attrs)
    |> Repo.update!()
  end

  def update_preferences!(player, preferences) do
    current_preferences = Map.from_struct(player.preferences)
    update_player!(player, %{preferences: Map.merge(current_preferences, preferences)})
  end

  def update_tutorial_step!(player, step), do: update_player!(player, %{tutorial_step: step})

  def old_update_ranking! do
    Repo.update_all(Player, set: [ranking: nil])

    PlayerQuery.old_ranking(1000)
    |> Repo.all()
    |> Enum.with_index(1)
    |> Enum.each(fn {player, index} ->
      update_player!(player, %{ranking: index, pvp_tier: pvp_tier_for(index)})
    end)
  end

  defp pvp_tier_for(n) when n in 1..5, do: 2
  defp pvp_tier_for(n) when n in 6..25, do: 1
  defp pvp_tier_for(_), do: 0

  def update_ranking! do
    immortals =
      PlayerQuery.with_pvp_tier(2) |> PlayerQuery.by_daily_wins() |> PlayerQuery.exclude_rankings([1]) |> Repo.all()

    shadows = PlayerQuery.with_pvp_tier(1) |> PlayerQuery.by_daily_wins() |> Repo.all()
    rest = PlayerQuery.with_pvp_tier(0) |> PlayerQuery.by_daily_wins() |> PlayerQuery.limit_by(975) |> Repo.all()

    rank_tiered_players!(immortals, 2)
    rank_tiered_players!(shadows, 6)
    rank_tiered_players!(rest, 26)
  end

  def update_ranking_tiers! do
    immortals = PlayerQuery.with_pvp_tier(2) |> PlayerQuery.by_daily_wins() |> Repo.all()
    shadows = PlayerQuery.with_pvp_tier(1) |> PlayerQuery.by_daily_wins() |> Repo.all()
    rest = PlayerQuery.with_pvp_tier(0) |> PlayerQuery.by_daily_wins() |> PlayerQuery.limit_by(975) |> Repo.all()
    deranked_immortals = Enum.slice(immortals, 1..4)
    new_immortals = Enum.slice(shadows, 0..3)
    deranked_shadows = Enum.slice(shadows, 14..19)
    same_shadows = Enum.slice(shadows, 4..13)
    ranked_rest = Enum.slice(rest, 0..5)
    the_immortal = List.first(immortals)

    new_shadows =
      deranked_immortals
      |> Kernel.++(same_shadows)
      |> Kernel.++(ranked_rest)

    new_rest =
      rest
      |> Kernel.--(ranked_rest)
      |> Kernel.++(deranked_shadows)

    the_immortal && update_player!(the_immortal, %{ranking: 1})

    new_immortals
    |> Enum.with_index(2)
    |> Enum.each(fn {player, index} ->
      update_player!(player, %{ranking: index, pvp_tier: 2})
    end)

    new_shadows
    |> Enum.with_index(6)
    |> Enum.each(fn {player, index} ->
      update_player!(player, %{ranking: index, pvp_tier: 1})
    end)

    new_rest
    |> Enum.sort_by(&{&1.daily_wins, &1.pvp_points}, :desc)
    |> Enum.with_index(26)
    |> Enum.each(fn {player, index} ->
      update_player!(player, %{ranking: index, pvp_tier: 0})
    end)
  end

  defp rank_tiered_players!(players, start_index) do
    players
    |> Enum.with_index(start_index)
    |> Enum.each(fn {player, index} ->
      update_player!(player, %{ranking: index})
    end)
  end
end
