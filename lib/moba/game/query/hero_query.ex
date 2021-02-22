defmodule Moba.Game.Query.HeroQuery do
  @moduledoc """
  Query functions for retrieving Heroes
  """

  alias Moba.Game
  alias Game.Schema.{Hero, Avatar}

  import Ecto.Query, only: [from: 2]

  @pvp_per_page Moba.pvp_heroes_per_page()
  @ranking_per_page Moba.ranking_heroes_per_page()

  def current_arena_players do
    non_bots() |> pvp_active()
  end

  def current_arena_bots do
    bots() |> pvp_active()
  end

  def pvp_search(exclude_list, filter, pvp_points, sort, page) do
    Hero
    |> pvp_active()
    |> exclude(exclude_list)
    |> pvp_filter(filter, pvp_points)
    |> pvp_sort(sort)
    |> limit_by(@pvp_per_page, page_to_offset(page, @pvp_per_page))
  end

  def paged_pvp_ranking(page) do
    Hero
    |> pvp_ranked()
    |> limit_by(@ranking_per_page, page_to_offset(page, @ranking_per_page))
  end

  def pve_targets(difficulty, level_range, exclude_list, current_match_id, codes, limit) do
    Hero
    |> by_difficulty(difficulty)
    |> pvp_inactive()
    |> by_level(level_range)
    |> by_match(current_match_id)
    |> by_codes(codes)
    |> exclude(exclude_list)
    |> limit_by(limit)
    |> random()
  end

  def league_defender(attacker_id, base_level, difficulty, current_match_id) do
    bots()
    |> by_level(base_level..base_level)
    |> by_match(current_match_id)
    |> by_difficulty(difficulty)
    |> exclude([attacker_id])
    |> random()
    |> limit_by(3)
  end

  def latest(user_id) do
    base = Hero |> by_user(user_id)

    from(hero in base,
      limit: 20,
      order_by: [desc: [hero.pvp_picks, hero.id]]
    )
  end

  def eligible_for_pvp(user_id) do
    from(hero in by_user(Hero, user_id),
      limit: 50,
      order_by: [desc: [hero.pvp_picks, hero.id]],
      where: hero.pve_battles_available == 0,
      where: hero.league_tier >= 4
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

  def last_active_pve(user_id, current_match_id) do
    base = by_user(Hero, user_id)

    from(hero in base,
      where: hero.match_id != ^current_match_id,
      order_by: [desc: hero.id],
      limit: 1
    )
  end

  def last_active_pvp(user_id) do
    base = by_user(Hero, user_id) |> pvp_inactive()

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

  def skynet_bot(time) do
    from(hero in current_arena_bots(),
      where: hero.pvp_last_picked <= ^time,
      limit: 1
    )
  end

  def weakest_pvp_bot do
    from(hero in current_arena_bots(),
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

  def by_difficulty(query, difficulty) do
    from hero in query,
      where: hero.bot_difficulty == ^difficulty
  end

  def by_level(query, first..last) do
    from hero in query,
      where: hero.level >= ^first,
      where: hero.level <= ^last
  end

  def by_match(query, match_id) do
    from hero in query,
      where: hero.match_id == ^match_id
  end

  def by_matches(match_ids, query \\ Hero) do
    from hero in query,
      where: hero.match_id in ^match_ids
  end

  def by_user(query, user_id) do
    from hero in query,
      where: hero.user_id == ^user_id
  end

  def by_users(query, user_ids) do
    from hero in query,
      where: hero.user_id in ^user_ids
  end

  def by_pvp_points(query, min, max) do
    from hero in query,
      where: hero.pvp_points >= ^min,
      where: hero.pvp_points <= ^max
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

  def by_total_farm(query, min, max) do
    from hero in query,
      where: hero.total_farm >= ^min,
      where: hero.total_farm <= ^max,
      order_by: [desc: hero.total_farm]
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

  def unarchived(query) do
    from hero in query,
      where: is_nil(hero.archived_at)
  end

  def finished_pve(query \\ Hero) do
    points_limit = Moba.pve_points_limit()

    from hero in query,
      where: hero.pve_battles_available == 0,
      where: hero.pve_points < ^points_limit,
      order_by: [desc: hero.total_farm]
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

  def exclude(query, ids) do
    from hero in query,
      where: hero.id not in ^ids
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

  defp page_to_offset(page, per_page) do
    result = (page - 1) * per_page

    if result < 0 do
      0
    else
      result
    end
  end
end
