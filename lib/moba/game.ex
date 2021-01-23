defmodule Moba.Game do
  @moduledoc """
  Top-level domain of all gameplay logic

  As a top-level domain, it can access its siblings like Engine and Accounts, its parent (Moba)
  and all of its children (Heroes, Matches, etc). It cannot, however, access children of its
  siblings.
  """

  alias Moba.{Repo, Game, Accounts}
  alias Game.{Heroes, Matches, Leagues, Targets, Items, Skills, Avatars, Builds}

  # MATCHES

  def current_match, do: Matches.current()

  def last_match, do: Matches.last_active()

  def create_match!(attrs \\ %{}), do: Matches.create!(attrs)

  def update_match!(match, attrs), do: Matches.update!(match, attrs)

  def podium_for(match), do: Matches.load_podium(match)

  # HEROES

  def get_hero!(hero_id), do: Heroes.get!(hero_id)

  def current_hero(user, "pve"), do: current_pve_hero(user)
  def current_hero(user, "pvp"), do: current_pvp_hero(user)

  def current_hero(nil), do: nil
  def current_hero(user), do: current_pvp_hero(user) || current_pve_hero(user)

  def current_pve_hero(%{current_pve_hero_id: hero_id}), do: get_hero!(hero_id)
  def current_pvp_hero(%{current_pvp_hero_id: hero_id}), do: get_hero!(hero_id)

  def current_heroes(user_id, match_id), do: Heroes.current(user_id, match_id)

  @doc """
  Users are only allowed to create 2 PVE heroes per match
  """
  def can_create_new_hero?(user) do
    match = current_match()

    match &&
      match.last_server_update_at &&
      length(current_heroes(user.id, match.id)) < 2
  end

  def last_pve_hero(user_id), do: Heroes.last_active_pve(user_id)

  def last_pvp_hero(user_id), do: Heroes.last_active_pvp(user_id)

  def latest_heroes(user_id), do: Heroes.list_latest(user_id)

  def eligible_heroes_for_pvp(user_id), do: Heroes.list_pvp_eligible(user_id)

  @doc """
  Orchestrates the creation of a Hero, which involves creating its initial build, activating it
  and generating its first Jungle targets
  """
  def create_hero!(attrs, user, avatar, skills, match \\ current_match()) do
    hero = Heroes.create!(attrs, user, avatar, match)
    build = Builds.create!("pve", hero, skills)

    hero
    |> activate_build!(build)
    |> generate_targets!()
  end

  def create_bot_hero!(avatar, level, difficulty, match, user \\ nil, pvp_points \\ 0) do
    league_tier = Leagues.tier_for(level)
    Heroes.create_bot!(avatar, level, difficulty, match, user, pvp_points, league_tier)
  end

  def update_hero!(hero, attrs, items \\ nil) do
    updated = Heroes.update!(hero, attrs, items)
    broadcast_to_hero(hero.id)
    updated
  end

  def update_attacker!(hero, updates), do: Heroes.update_attacker!(hero, updates)

  @doc """
  When a Hero is picked for the Arena, it needs to have its inventory and skills updated
  to reflect current values in the admin panel, since Heroes can stay "benched" for a long time
  """
  def prepare_hero_for_pvp!(hero) do
    hero
    |> Builds.update_all_with_current_skills!()
    |> Items.replace_inventory_with_current!()
    |> Heroes.prepare_for_pvp!()
  end

  def max_league?(%{league_tier: tier}), do: tier == Moba.max_league_tier()

  def pve_win_rate(hero), do: Heroes.pve_win_rate(hero)

  def pvp_win_rate(hero), do: Heroes.pvp_win_rate(hero)

  def pvp_search(hero, sort \\ "level"), do: Heroes.pvp_search(hero, sort)

  def pvp_search(hero, filter, sort, page), do: Heroes.pvp_search(hero, filter, sort, page)

  def ranking(limit \\ 20), do: Heroes.ranking(limit)

  def paged_ranking(page), do: Heroes.paged_ranking(page)

  def update_ranking!, do: Heroes.update_ranking!()

  def redeem_league!(hero), do: Heroes.redeem_league!(hero)

  def level_cheat(hero), do: Heroes.level_cheat(hero)

  def hero_has_other_build?(hero), do: Heroes.has_other_build?(hero)

  def pvp_targets_available(hero), do: Heroes.pvp_targets_available(hero)

  def subscribe_to_hero(hero_id) do
    MobaWeb.subscribe("hero-#{hero_id}")
    hero_id
  end

  def broadcast_to_hero(hero_id) do
    MobaWeb.broadcast("hero-#{hero_id}", "hero", %{id: hero_id})
  end

  # BUILDS

  def get_build!(build_id), do: Builds.get!(build_id)

  def update_build!(build, attrs), do: Builds.update!(build, attrs)

  def replace_build_skills!(build, new_skills), do: Builds.replace_skills!(build, new_skills)

  @doc """
  Creating a new PVP build also means giving the Hero all the skill levels necessary
  for it to level up its new Skills
  """
  def create_pvp_build!(hero, skills) do
    levels = Skills.levels_available_for(hero.level)
    hero = update_hero!(hero, %{skill_levels_available: levels})
    build = Builds.create!("pvp", hero, skills)
    activate_build!(build.hero, build)
  end

  @doc """
  Heroes can freely switch between builds when in the Arena
  """
  def switch_build!(hero) do
    build = Builds.other_build_for(hero)
    activate_build!(hero, build)
  end

  def generate_bot_build!(bot) do
    build = Builds.generate_for_bot!(bot)
    activate_build!(build.hero, build)
  end

  def activate_build!(hero, build) do
    hero
    |> update_hero!(%{active_build_id: build.id})
    |> Map.put(:active_build, build)
  end

  def skill_builds_for(role), do: Builds.skill_builds_for(role)

  def skill_build_for(avatar, index), do: Builds.skill_build_for(avatar, index)

  def reset_item_orders!(hero), do: Builds.reset_item_orders!(hero)

  # LEAGUES

  def max_league_step_for(league), do: Leagues.max_step_for(league)

  def league_tier_for(level), do: Leagues.tier_for(level)

  def league_defender_for(attacker), do: Leagues.defender_for(attacker)

  # TARGETS

  def get_target!(target_id), do: Targets.get!(target_id)

  def generate_targets!(hero) do
    hero = Repo.preload(hero, :user)
    codes = hero.user && Accounts.unlocked_codes_for(hero.user) || []
    Targets.generate!(hero, codes)
  end

  def list_targets(hero_id), do: Targets.list(hero_id)

  # ITEMS

  def get_item!(item_id), do: Items.get!(item_id)

  def get_item_by_code!(code), do: Items.get_by_code!(code)

  def shop_list, do: Items.shop_list()

  def buy_item!(hero, item), do: Items.buy!(hero, item)

  def sell_item!(hero, item), do: Items.sell!(hero, item)

  def transmute_item!(hero, recipe, item), do: Items.transmute!(hero, recipe, item)

  def previous_rarity_item(item), do: Items.previous_rarity_for(item)

  def item_ingredients_count(item), do: Items.ingredients_count_for(item)

  def item_price(item), do: Items.price(item)

  def item_sell_price(item), do: Items.sell_price(item)

  def can_equip_item?(hero, item), do: Items.can_equip?(hero, item)

  def can_buy_item?(hero, item), do: Items.can_buy?(hero, item)

  def sort_items(list), do: Items.sort(list)

  # SKILLS

  def basic_attack, do: Skills.basic_attack()

  def get_skill!(skill_id), do: Skills.get!(skill_id)

  def get_skill_by_code!(code, current, level \\ 1), do: Skills.get_by_code!(code, current, level)

  def get_current_skill!(code, level \\ 1), do: Skills.get_by_code!(code, true, level)

  def level_up_skill!(hero, skill), do: Skills.level_up!(hero, skill)

  def can_level_skill?(hero, skill), do: Skills.can_level?(hero, skill)

  def max_skill_level(skill), do: Skills.max_level(skill)

  def get_current_skills_from(skills), do: Skills.get_current_from(skills)

  def list_normal_skills, do: Skills.list_normals()

  def list_ultimate_skills, do: Skills.list_ultimates()

  def list_creation_skills(level, codes \\ []), do: Skills.list_creation(level, codes)

  def list_chosen_skills(skill_ids), do: Skills.list_chosen(skill_ids)

  def list_unlockable_skills, do: Skills.list_unlockable()

  def ordered_skills_query, do: Skills.ordered_query()

  # AVATARS

  def get_avatar!(avatar_id), do: Avatars.get!(avatar_id)

  def get_avatar_by_code!(code), do: Avatars.get_by_code!(code)

  def create_avatar!(avatar, attrs, match \\ nil), do: Avatars.create!(avatar, attrs, match)

  def list_avatars, do: Avatars.list()

  def list_creation_avatars(codes \\ []), do: Avatars.creation_list(codes)

  def list_unlockable_avatars, do: Avatars.unlockable_list()
end
