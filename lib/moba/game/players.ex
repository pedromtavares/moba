defmodule Moba.Game.Players do
  @moduledoc """
  Manages Match records and queries.
  See Moba.Game.Schema.Match for more info.
  """

  alias Moba.{Repo, Game}
  alias Game.Schema.Player
  alias Game.Query.{HeroQuery, PlayerQuery}
  import Ecto.Query

  def add_total_farm!(%{player: player} = hero) do
    update_player!(player, %{total_farm: player.total_farm + hero.total_gold_farm + hero.total_xp_farm})
  end

  def bot_ranking, do: PlayerQuery.current_season() |> PlayerQuery.bots() |> PlayerQuery.by_pvp_points() |> Repo.all()

  def create_player!(attrs \\ %{}) do
    {:ok, player} =
      Repo.transaction(fn ->
        user_id = attrs[:user_id] || attrs["user_id"]
        if user_id, do: Repo.one!(from u in Moba.Accounts.Schema.User, where: u.id == ^user_id, lock: "FOR UPDATE")
        existing = user_id && get_player_from_user!(user_id)

        existing ||
          %Player{season_id: Game.current_season().id}
          |> Player.changeset(attrs)
          |> Repo.insert!()
      end)

    player
  end

  def duel_opponent(player), do: matchmaking_opponent(player)

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
    {:ok, updated} =
      Repo.transaction(fn ->
        player = Map.fetch!(lock_players!([player.id]), player.id)
        loser_id = updates[:loser_id] && Integer.to_string(updates[:loser_id])

        duel_score =
          if loser_id do
            Map.update(player.duel_score, loser_id, 1, &(&1 + 1))
          else
            player.duel_score
          end

        update_player!(player, %{
          duel_score: duel_score,
          pvp_points: max(0, player.pvp_points + Map.get(updates, :rating_change, 0))
        })
      end)

    updated
  end

  @doc "Locks players in a stable order inside the caller's transaction before calculating a result."
  def lock_players!(ids) do
    Repo.all(from p in Player, where: p.id in ^ids, order_by: p.id, lock: "FOR UPDATE")
    |> Map.new(&{&1.id, &1})
  end

  def get_player!(id), do: PlayerQuery.load() |> Repo.get!(id)

  def get_player_from_user!(user_id) do
    season_id = Game.current_season().id
    Repo.one(from p in PlayerQuery.load(), where: p.user_id == ^user_id and p.season_id == ^season_id, limit: 1)
  end

  def matchmaking_opponent(%{pvp_tier: 0, id: id, pvp_points: points}) do
    pleb = PlayerQuery.pleb_opponents(id, points) |> Repo.all() |> List.first()
    pleb || PlayerQuery.matchmaking_opponents(id, 0) |> Repo.all() |> List.first()
  end

  def matchmaking_opponent(%{pvp_tier: tier, id: id}) do
    PlayerQuery.matchmaking_opponents(id, tier) |> Repo.all() |> List.first()
  end

  @doc """
  Lists Players by their ranking
  """
  def daily_ranking(limit), do: PlayerQuery.daily_ranked(limit) |> Repo.all()

  def season_points_ranking(limit), do: PlayerQuery.season_points_ranked(limit) |> Repo.all()

  def arena_ranking_neighbors(%{ranking: rank} = player, "3v3") when is_integer(rank) do
    ranking = PlayerQuery.daily_ranked()
    previous = from p in ranking, where: p.ranking < ^rank
    following = from p in ranking, where: p.ranking > ^rank
    {higher, lower} = ranking_neighbors(previous, following)

    Enum.map(higher ++ [player | lower], &{&1, &1.ranking})
  end

  def arena_ranking_neighbors(%{id: id, user_id: user_id, bot_options: nil, pvp_points: points} = player, "1v1")
      when not is_nil(user_id) do
    if player.season_id == Game.current_season().id do
      ranking = PlayerQuery.season_points_ranked()
      previous = from p in ranking, where: p.pvp_points > ^points or (p.pvp_points == ^points and p.id < ^id)
      following = from p in ranking, where: p.pvp_points < ^points or (p.pvp_points == ^points and p.id > ^id)
      {higher, lower} = ranking_neighbors(previous, following)
      position = Repo.aggregate(previous, :count) + 1

      Enum.with_index(higher ++ [player | lower], position - length(higher))
    else
      []
    end
  end

  def arena_ranking_neighbors(_, _), do: []

  defp ranking_neighbors(previous, following) do
    higher = previous |> reverse_order() |> limit(4) |> Repo.all()
    lower = following |> limit(4) |> Repo.all()
    higher_count = min(length(higher), max(2, 4 - length(lower)))

    {higher |> Enum.take(higher_count) |> Enum.reverse(), Enum.take(lower, 4 - higher_count)}
  end

  def season_ranking(limit) do
    players = PlayerQuery.season_ranked(limit) |> Repo.all()

    top_heroes =
      players
      |> Enum.map(& &1.id)
      |> HeroQuery.top_ranked_for_players()
      |> Repo.all()
      |> Map.new(&{&1.player_id, &1})

    Enum.map(players, &Map.put(&1, :top_hero, Map.get(top_heroes, &1.id)))
  end

  def set_player_available!(player), do: update_player!(player, %{status: "available"})

  def set_player_unavailable!(player), do: update_player!(player, %{status: "unavailable"})

  def set_current_pve_hero!(player, hero_id), do: update_player!(player, %{current_pve_hero_id: hero_id})

  def update_collection!(player, hero_collection) do
    update_player!(player, %{hero_collection: hero_collection})
  end

  def update_player!(%Player{} = player, attrs) do
    changeset = Player.changeset(player, attrs)
    player = Repo.update!(changeset)

    if Map.has_key?(changeset.changes, :status) do
      MobaWeb.broadcast("online", "availability", %{player_id: player.id})
    end

    player
  end

  def touch_guest(%Player{user_id: nil, id: id}) do
    cutoff = NaiveDateTime.utc_now() |> NaiveDateTime.add(-60)

    Repo.update_all(from(p in Player, where: p.id == ^id and is_nil(p.user_id) and p.updated_at < ^cutoff),
      set: [updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)]
    )
  end

  def update_preferences!(player, preferences) do
    {:ok, player} =
      Repo.transaction(fn ->
        current = Repo.one!(from p in Player, where: p.id == ^player.id, lock: "FOR UPDATE")
        saved = if current.preferences, do: Map.from_struct(current.preferences), else: %{}
        update_player!(%{player | preferences: current.preferences}, %{preferences: Map.merge(saved, preferences)})
      end)

    player
  end

  def update_tutorial_step!(player, step), do: update_player!(player, %{tutorial_step: step})

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

    the_immortal && update_immortal!(the_immortal)

    new_immortals
    |> Enum.with_index(2)
    |> Enum.each(fn {player, index} ->
      update_player!(player, %{ranking: index, pvp_tier: 2})
    end)

    new_shadows
    |> Enum.with_index(6)
    |> Enum.each(fn {player, index} ->
      update_player!(player, %{ranking: index, pvp_tier: 1, current_immortal_streak: 0})
    end)

    new_rest
    |> Enum.sort_by(&{&1.daily_wins, &1.pvp_points}, :desc)
    |> Enum.with_index(26)
    |> Enum.each(fn {player, index} ->
      update_player!(player, %{ranking: index, pvp_tier: 0})
    end)
  end

  def update_season_ranking! do
    Repo.update_all(PlayerQuery.current_season(), set: [season_ranking: nil])

    PlayerQuery.season_ranking(1000)
    |> Repo.all()
    |> Enum.with_index(1)
    |> Enum.each(fn {player, index} ->
      update_player!(player, %{season_ranking: index})
    end)
  end

  defp rank_tiered_players!(players, start_index) do
    players
    |> Enum.with_index(start_index)
    |> Enum.each(fn {player, index} ->
      update_player!(player, %{ranking: index})
    end)
  end

  defp update_immortal!(%{current_immortal_streak: cstreak, best_immortal_streak: bstreak} = player) do
    current = cstreak + 1
    best = if current > bstreak, do: current, else: bstreak
    update_player!(player, %{ranking: 1, best_immortal_streak: best, current_immortal_streak: current})
  end
end
