defmodule Moba.Game.Query.HeroQuery do
  @moduledoc """
  Query functions for retrieving Heroes
  """

  alias Moba.Game
  alias Game.Schema.{Hero, Avatar}
  alias Game.Query.SkillQuery

  import Ecto.Query

  @pvp_per_page Moba.pvp_heroes_per_page()
  @ranking_per_page Moba.ranking_heroes_per_page()
  @current_ranking_date Moba.current_ranking_date()

  def load(queryable \\ Hero) do
    queryable
    |> preload([:items, :avatar, :skin, :user, active_build: [skills: ^SkillQuery.ordered()]])
  end

  def load_avatar(queryable \\ Hero) do
    preload(queryable, [:avatar])
  end

  def current_arena_players do
    non_bots() |> pvp_active()
  end

  def current_arena_bots(league_tier) do
    bots() |> pvp_active() |> with_league_tier(league_tier)
  end

  def pvp_search(exclude_list, filter, pvp_points, league_tier, sort, page) do
    Hero
    |> pvp_active()
    |> with_league_tier(league_tier)
    |> exclude_ids(exclude_list)
    |> pvp_filter(filter, pvp_points)
    |> pvp_sort(sort)
    |> limit_by(@pvp_per_page, page_to_offset(page, @pvp_per_page))
  end

  def paged_pvp_ranking(page) do
    Hero
    |> pvp_ranked()
    |> limit_by(@ranking_per_page, page_to_offset(page, @ranking_per_page))
  end

  def pve_targets(difficulty, farm_range, exclude_list, codes, limit) do
    Hero
    |> by_difficulty(difficulty)
    |> pvp_inactive()
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

  def latest(user_id, limit \\ 50) do
    base = Hero |> with_user(user_id)

    from(hero in base,
      limit: ^limit,
      order_by: [desc: [hero.id]],
      where: is_nil(hero.archived_at)
    )
  end

  def eligible_for_pvp(user_id) do
    from(hero in with_user(Hero, user_id),
      limit: 50,
      order_by: [desc: [hero.pvp_picks, hero.id]],
      where: not is_nil(hero.finished_at),
      where: hero.league_tier >= 3,
      where: hero.inserted_at > ^@current_ranking_date
    )
  end

  def eligible_for_fame do
    match_players = non_bots() |> non_retired()
    ago = Timex.now() |> Timex.shift(days: -7)

    from(h in match_players,
      order_by: [desc: h.pvp_points],
      limit: 20,
      where: h.inserted_at > ^ago,
      where: h.pvp_points > 0,
      where: not is_nil(h.pvp_points)
    )
  end

  def pvp_last_picked(user_id) do
    base = with_user(Hero, user_id) |> pvp_inactive()

    from(hero in base,
      order_by: [desc: hero.pvp_last_picked],
      where: not is_nil(hero.pvp_last_picked),
      limit: 1
    )
  end

  def pvp_picked_recently(match_time) do
    ago = match_time |> Timex.shift(days: -3)

    from(hero in Hero,
      where: not is_nil(hero.pvp_last_picked),
      where: hero.pvp_last_picked > ^ago
    )
  end

  def skynet_bot(league_tier, time) do
    from(hero in current_arena_bots(league_tier),
      where: hero.pvp_last_picked <= ^time,
      limit: 1
    )
  end

  def weakest_pvp_bot(league_tier) do
    from(hero in current_arena_bots(league_tier),
      order_by: [asc: hero.pvp_points],
      limit: 1
    )
  end

  def non_bots(query \\ Hero) do
    from hero in query,
      where: is_nil(hero.bot_difficulty)
  end

  def bots(query \\ Hero) do
    from hero in query,
      where: not is_nil(hero.bot_difficulty)
  end

  def pve_bots(query \\ bots()) do
    from hero in query, where: is_nil(hero.user_id)
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

  def with_user(query, user_id) do
    from hero in query,
      where: hero.user_id == ^user_id
  end

  def by_pvp_points(query, min, max) do
    from hero in query,
      where: hero.pvp_points >= ^min,
      where: hero.pvp_points <= ^max
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
    from hero in query, where: hero.inserted_at > ^@current_ranking_date
  end

  def pvp_ranked(query \\ Hero) do
    from hero in pvp_active(query),
      where: not is_nil(hero.pvp_ranking),
      order_by: [asc: hero.pvp_ranking]
  end

  def pve_ranked(query \\ Hero) do
    from hero in non_bots(query),
      where: not is_nil(hero.pve_ranking),
      order_by: [asc: hero.pve_ranking]
  end

  def non_retired(query \\ Hero) do
    from hero in query,
      where: not is_nil(hero.pvp_points)
  end

  def with_pvp_points(query \\ pvp_active()) do
    from hero in query,
      order_by: [desc: hero.pvp_points]
  end

  def exclude_ids(query, ids) do
    from hero in query,
      where: hero.id not in ^ids
  end

  def exclude_match(%{id: id} = _match) do
    from hero in Hero, where: hero.match_id != ^id
  end

  def pvp_active(query \\ Hero) do
    from hero in query,
      where: hero.pvp_active == true
  end

  def pvp_inactive(query \\ Hero) do
    from hero in query,
      where: hero.pvp_active == false
  end

  def pvp_filter(query, nil, _), do: query

  def pvp_filter(query, filter, pvp_points) when filter == "easy" do
    by_pvp_points(query, 0, pvp_points - 41)
  end

  def pvp_filter(query, filter, pvp_points) when filter == "normal" do
    by_pvp_points(query, pvp_points - 40, pvp_points + 40)
  end

  def pvp_filter(query, filter, pvp_points) when filter == "hard" do
    by_pvp_points(query, pvp_points + 41, pvp_points + 80)
  end

  def pvp_filter(query, filter, pvp_points) when filter == "hardest" do
    by_pvp_points(query, pvp_points + 81, 10000)
  end

  def pvp_sort(query, nil), do: query

  def pvp_sort(query, "level") do
    from hero in query,
      order_by: [asc: hero.level, asc: hero.experience, asc: hero.pvp_ranking]
  end

  def pvp_sort(query, "hp") do
    from hero in query,
      order_by: [asc: hero.total_hp + hero.item_hp, asc: hero.pvp_ranking]
  end

  def pvp_sort(query, "atk") do
    from hero in query,
      order_by: [asc: hero.atk + hero.item_atk, asc: hero.pvp_ranking]
  end

  def pvp_sort(query, "random") do
    random(query)
  end

  def created_recently(query \\ non_bots(), hours_ago \\ 24) do
    ago = Timex.now() |> Timex.shift(hours: -hours_ago)

    from(hero in query,
      join: user in assoc(hero, :user),
      where: hero.inserted_at > ^ago,
      where: user.is_guest == false,
      where: user.is_bot == false
    )
  end

  def with_avatar_ids(query, avatar_ids) do
    from hero in query, where: hero.avatar_id in ^avatar_ids
  end

  def created_before(query, time) do
    from hero in query, where: hero.inserted_at < ^time
  end

  defp page_to_offset(page, per_page) do
    result = (page - 1) * per_page

    if result < 0 do
      0
    else
      result
    end
  end
end
