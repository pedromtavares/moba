defmodule Moba.Game.Query.HeroQuery do
  @moduledoc """
  Query functions for retrieving Heroes
  """

  alias Moba.Game
  alias Game.Schema.{Hero, Avatar}
  alias Game.Query.SkillQuery

  import Ecto.Query

  @platinum_league_tier Moba.platinum_league_tier()
  @master_league_tier Moba.master_league_tier()
  @current_ranking_date Moba.current_ranking_date()
  @base_hero_count Moba.base_hero_count()

  def load(queryable \\ Hero) do
    queryable
    |> preload([
      :items,
      :avatar,
      :skin,
      player: :user,
      skills: ^SkillQuery.ordered()
    ])
  end

  def load_avatar(queryable \\ Hero) do
    preload(queryable, [:avatar])
  end

  def trained(player_id, ids, limit) do
    base = with_player(load(), player_id) |> unarchived() |> finished() |> order_by_pvp() |> exclude_ids(ids)

    from(hero in base,
      limit: ^limit,
      where: hero.league_tier >= @platinum_league_tier
    )
  end

  def pve_targets(difficulty, farm_range, exclude_list, codes, limit) do
    Hero
    |> by_difficulty(difficulty)
    |> by_total_xp_farm(farm_range)
    |> by_codes(codes)
    |> exclude_ids(exclude_list)
    |> limit_by(limit)
    |> unarchived()
    |> random()
  end

  def league_defender(attacker_id, base_level, difficulty) do
    bots()
    |> by_level(base_level..base_level)
    |> by_difficulty(difficulty)
    |> exclude_ids([attacker_id])
    |> random()
    |> unarchived()
    |> limit_by(1)
  end

  def latest(player_id, limit \\ @base_hero_count) do
    base = load() |> with_player(player_id) |> unarchived()

    from(hero in base, limit: ^limit, order_by: [desc: [hero.inserted_at]])
  end

  def finished(query) do
    from(hero in query, where: not is_nil(hero.finished_at))
  end

  def unfinished(query) do
    from(hero in query, where: is_nil(hero.finished_at))
  end

  def pvp_picked_recently(match_time) do
    ago = match_time |> Timex.shift(days: -3)

    from(hero in Hero,
      where: not is_nil(hero.pvp_last_picked),
      where: hero.pvp_last_picked > ^ago
    )
  end

  def non_bots(query \\ Hero) do
    from hero in query, where: is_nil(hero.bot_difficulty)
  end

  def bots(query \\ Hero) do
    from hero in query, where: not is_nil(hero.bot_difficulty)
  end

  def pvp_bots(difficulty, league_tier) do
    bots()
    |> by_difficulty(difficulty)
    |> with_league_tier(league_tier)
    |> by_level(15..26)
    |> random()
    |> unarchived()
    |> load()
  end

  def by_difficulty(query, difficulty) do
    from hero in query,
      where: hero.bot_difficulty == ^difficulty
  end

  def by_level(query, first..last) do
    from hero in query,
      where: hero.level >= ^first,
      where: hero.level <= ^last
  end

  def by_total_xp_farm(query, first..last) do
    from hero in query,
      where: hero.total_xp_farm >= ^first,
      where: hero.total_xp_farm <= ^last
  end

  def with_player(query, player_id) do
    from hero in query,
      where: hero.player_id == ^player_id
  end

  def with_league_tier(query, league_tier) do
    from hero in query,
      where: hero.league_tier == ^league_tier
  end

  def with_league_tiers(query, league_tiers) do
    from hero in query,
      where: hero.league_tier in ^league_tiers
  end

  def by_codes(query, codes) do
    from hero in query,
      join: avatar in Avatar,
      on: hero.avatar_id == avatar.id,
      where: is_nil(avatar.level_requirement) or avatar.code in ^codes
  end

  def by_pve_ranking(query, min, max) do
    from hero in query,
      where: hero.pve_ranking >= ^min,
      where: hero.pve_ranking <= ^max,
      order_by: [asc: hero.pve_ranking]
  end

  def by_total_gold_farm(query, min, max) do
    from hero in query,
      where: hero.total_gold_farm >= ^min,
      where: hero.total_gold_farm <= ^max,
      where: not is_nil(hero.pve_ranking),
      order_by: [desc: hero.total_gold_farm]
  end

  def limit_by(query, limit, offset \\ 0) do
    from hero in query,
      limit: ^limit,
      offset: ^offset
  end

  def random(query) do
    from hero in query,
      order_by: fragment("RANDOM()")
  end

  def unarchived(query \\ Hero) do
    from hero in query,
      where: is_nil(hero.archived_at)
  end

  def finished_pve(query \\ Hero) do
    from hero in query,
      where: not is_nil(hero.finished_at),
      order_by: [
        desc: fragment("? + ?", hero.total_xp_farm, hero.total_gold_farm),
        desc: fragment("? - ?", hero.inserted_at, hero.finished_at)
      ]
  end

  def in_current_ranking_date(query \\ Hero) do
    last_week = Timex.now() |> Timex.shift(days: -7)

    from hero in query,
      where:
        (hero.league_tier >= ^@master_league_tier and hero.inserted_at > ^@current_ranking_date) or
          hero.inserted_at > ^last_week
  end

  def pve_ranked(query \\ Hero) do
    from hero in non_bots(query),
      where: not is_nil(hero.pve_ranking),
      order_by: [asc: hero.pve_ranking]
  end

  def exclude_ids(query, ids) do
    ids = Enum.filter(ids, & &1)
    if length(ids) > 0, do: from(hero in query, where: hero.id not in ^ids), else: query
  end

  def created_recently(query \\ non_bots(), hours_ago \\ 24) do
    ago = Timex.now() |> Timex.shift(hours: -hours_ago)

    from(hero in query,
      join: player in assoc(hero, :player),
      where: hero.inserted_at > ^ago,
      where: not is_nil(player.user_id),
      where: is_nil(player.bot_options)
    )
  end

  def with_avatar_ids(query, avatar_ids) do
    from hero in query, where: hero.avatar_id in ^avatar_ids
  end

  def with_ids(query, hero_ids) do
    from hero in query, where: hero.id in ^hero_ids
  end

  def created_before(query, time) do
    from hero in query, where: hero.inserted_at < ^time
  end

  def order_by_pvp(query) do
    from hero in query, order_by: [desc: [hero.total_gold_farm + hero.total_xp_farm]]
  end

  def finished_recently(query \\ non_bots(), hours_ago \\ 1) do
    ago = Timex.now() |> Timex.shift(hours: -hours_ago)
    from hero in query, where: hero.finished_at > ^ago
  end

  def unranked(query \\ Hero) do
    from hero in query, where: is_nil(hero.pve_ranking)
  end
end
