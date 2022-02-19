defmodule Moba.Game do
  @moduledoc """
  Top-level domain of all gameplay logic

  As a top-level domain, it can access its siblings like Engine and Accounts, its parent (Moba)
  and all of its children (Heroes, Matches, etc). It cannot, however, access children of its
  siblings.
  """

  alias Moba.{Repo, Game, Accounts}
  alias Game.{Heroes, Matches, Leagues, Targets, Items, Skills, Avatars, Builds, ArenaPicks, Skins, Duels, Quests}

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

  def last_picked_pvp_hero(user_id), do: Heroes.pvp_last_picked(user_id)

  def latest_heroes(user_id), do: Heroes.list_latest(user_id)

  def eligible_heroes_for_pvp(user_id), do: Heroes.list_pvp_eligible(user_id)

  @doc """
  Orchestrates the creation of a Hero, which involves creating its initial build, activating it
  and generating its first Jungle targets
  """
  def create_hero!(attrs, user, avatar, skills) do
    attrs =
      if user && user.pve_tier >= 4 do
        Map.put(attrs, :refresh_targets_count, Moba.refresh_targets_count(user.pve_tier))
      else
        attrs
      end

    hero = Heroes.create!(attrs, user, avatar)
    build = Builds.create!("pve", hero, skills)

    hero
    |> activate_build!(build)
    |> generate_targets!()
  end

  def create_bot_hero!(avatar, level, difficulty, user \\ nil, pvp_points \\ 0) do
    league_tier = Leagues.tier_for(level)
    Heroes.create_bot!(avatar, level, difficulty, user, pvp_points, league_tier)
  end

  def create_pvp_bot_hero!(user, avatar) do
    difficulty = if user.bot_tier == Moba.master_league_tier(), do: "pvp_master", else: "pvp_grandmaster"
    Heroes.create_bot!(avatar, 25, difficulty, user, 0, user.bot_tier)
  end

  def update_hero!(hero, attrs, items \\ nil) do
    updated = Heroes.update!(hero, attrs, items)
    broadcast_to_hero(hero.id)
    updated
  end

  def update_attacker!(hero, updates) do
    updated = Heroes.update_attacker!(hero, updates)
    broadcast_to_hero(hero.id)
    updated
  end

  def prepare_hero_for_pvp!(hero), do: Heroes.prepare_for_pvp!(hero)

  def archive_hero!(%{user: user} = hero) do
    if user.current_pve_hero_id == hero.id, do: Accounts.set_current_pve_hero!(user, nil)
    update_hero!(hero, %{archived_at: DateTime.utc_now()})
  end

  def refresh_targets!(%{refresh_targets_count: count} = hero) when count > 0 do
    generate_targets!(hero)

    update_hero!(hero, %{refresh_targets_count: count - 1})
  end

  def refresh_targets!(hero), do: hero

  def master_league?(%{league_tier: tier}), do: tier == Moba.master_league_tier()

  def max_league?(%{league_tier: league_tier, pve_tier: pve_tier}),
    do: league_tier == Moba.max_available_league(pve_tier)

  def pve_win_rate(hero), do: Heroes.pve_win_rate(hero)

  def pvp_win_rate(hero), do: Heroes.pvp_win_rate(hero)

  def pvp_search(hero, sort \\ "level"), do: Heroes.pvp_search(hero, sort)

  def pvp_search(hero, filter, sort, page), do: Heroes.pvp_search(hero, filter, sort, page)

  def pvp_ranking(league_tier, limit), do: Heroes.pvp_ranking(league_tier, limit)

  def paged_pvp_ranking(league_tier, page), do: Heroes.paged_pvp_ranking(league_tier, page)

  defdelegate update_pvp_ranking!(league_tier), to: Heroes

  def update_pvp_rankings!, do: update_pvp_ranking!(5) && update_pvp_ranking!(6)

  def pve_search(hero), do: Heroes.pve_search(hero)

  def pve_ranking(limit \\ 20), do: Heroes.pve_ranking(limit)

  def update_pve_ranking!, do: Heroes.update_pve_ranking!()

  defdelegate prepare_league_challenge!(hero), to: Heroes

  def level_cheat(hero), do: Heroes.level_cheat(hero)

  def hero_has_other_build?(hero), do: Heroes.has_other_build?(hero)

  def pvp_targets_available(hero), do: Heroes.pvp_targets_available(hero)

  def set_hero_skin!(hero, skin), do: Heroes.set_skin!(hero, skin)

  def veteran_hero?(%{pve_tier: tier}) when tier >= 2, do: true
  def veteran_hero?(_), do: false

  def maybe_generate_boss(
        %{pve_current_turns: 5, pve_total_turns: 0, boss_id: nil, pve_state: "alive", league_tier: 5} = hero
      ) do
    generate_boss!(hero)
  end

  def maybe_generate_boss(hero), do: hero

  def maybe_finish_pve(
        %{pve_state: state, pve_current_turns: 0, pve_total_turns: 0, boss_id: nil, finished_at: nil} = hero
      ) do
    if max_league?(hero) || master_league?(hero) || state == "dead" do
      finish_pve!(hero)
    else
      hero
    end
  end

  def maybe_finish_pve(hero), do: hero

  def finish_pve!(%{finished_at: nil} = hero) do
    hero
    |> update_hero!(%{finished_at: Timex.now()})
    |> update_hero_collection!()
    |> track_pve_quests()
  end

  def finish_pve!(hero), do: hero

  def generate_boss!(hero) do
    boss =
      Heroes.create!(
        %{name: "Roshan", league_tier: 6, level: 25, bot_difficulty: "boss", boss_id: hero.id},
        nil,
        Avatars.boss!()
      )

    build = Builds.create!("pve", boss, Skills.boss!())

    activate_build!(boss, build)

    update_hero!(hero, %{boss_id: boss.id})
  end

  def finalize_boss!(%{league_attempts: 0} = boss, boss_current_hp, hero) do
    maximum_hp = boss.avatar.total_hp
    new_total = boss_current_hp + Moba.boss_regeneration_multiplier() * maximum_hp
    new_total = if new_total > maximum_hp, do: maximum_hp, else: trunc(new_total)
    update_hero!(boss, %{total_hp: new_total, league_attempts: 1})
    update_hero!(hero, %{pve_state: "dead"})
  end

  def finalize_boss!(_, _, hero), do: update_hero!(hero, %{boss_id: nil, pve_state: "dead"})

  defdelegate buyback!(hero), to: Heroes

  defdelegate buyback_price(hero), to: Heroes

  defdelegate start_farming!(hero, state, turns), to: Heroes

  def finish_farming!(hero) do
    hero
    |> Heroes.finish_farming!()
    |> generate_targets!()
  end

  def update_hero_collection!(hero) do
    hero = Repo.preload(hero, :user)
    collection = Heroes.collection_for(hero.user_id)
    Accounts.update_collection!(hero.user, collection)

    hero
  end

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
    %{hero: hero} = build = Builds.create!("pvp", hero, skills)

    hero
    |> activate_build!(build)
    |> level_active_build_to_max!()
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

  defdelegate skill_builds_for(role), to: Builds

  defdelegate skill_build_for(avatar, index), to: Builds

  defdelegate reset_item_orders!(hero, new_inventory), to: Builds

  def level_active_build_to_max!(hero), do: Builds.level_active_to_max!(hero)

  # LEAGUES

  def max_league_step_for(league), do: Leagues.max_step_for(league)

  def league_tier_for(level), do: Leagues.tier_for(level)

  def league_defender_for(attacker), do: Leagues.defender_for(attacker)

  # TARGETS

  def get_target!(target_id), do: Targets.get!(target_id)

  def generate_targets!(hero) do
    hero = Repo.preload(hero, :user)
    codes = (hero.user && Accounts.unlocked_codes_for(hero.user)) || []
    Targets.generate!(hero, codes)
  end

  def list_targets(hero) do
    farm_sort = if veteran_hero?(hero), do: :desc, else: :asc
    Targets.list(hero.id, farm_sort)
  end

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

  def max_leveled_skills(skills), do: Skills.max_levels(skills)

  def get_current_skills_from(skills), do: Skills.get_current_from(skills)

  def list_normal_skills, do: Skills.list_normals()

  def list_ultimate_skills, do: Skills.list_ultimates()

  def list_creation_skills(level, codes \\ []), do: Skills.list_creation(level, codes)

  def list_chosen_skills(skill_ids), do: Skills.list_chosen(skill_ids)

  def list_unlockable_skills, do: Skills.list_unlockable()

  # AVATARS

  def get_avatar!(avatar_id), do: Avatars.get!(avatar_id)

  def get_avatar_by_code!(code), do: Avatars.get_by_code!(code)

  def create_avatar!(avatar, attrs, match \\ nil), do: Avatars.create!(avatar, attrs, match)

  def list_avatars, do: Avatars.list()

  def list_creation_avatars(codes \\ []), do: Avatars.creation_list(codes)

  def list_unlockable_avatars, do: Avatars.unlockable_list()

  # ARENA PICKS

  def create_arena_pick!(user, match), do: ArenaPicks.create!(user, match)

  def list_recent_arena_picks(user), do: ArenaPicks.list_recent(user)

  # SKINS

  def list_skins_for(avatar_code), do: Skins.list_for(avatar_code)

  def list_skins_with_codes(codes), do: Skins.list_with_codes(codes)

  def get_skin_by_code!(code), do: Skins.get_by_code!(code)

  def default_skin(avatar_code), do: Skins.default(avatar_code)

  # DUELS

  def get_duel!(id), do: Duels.get!(id)

  def create_duel!(user, opponent) do
    duel = Duels.create!(user, opponent)
    MobaWeb.broadcast("user-#{user.id}", "duel", %{id: duel.id})
    MobaWeb.broadcast("user-#{opponent.id}", "duel", %{id: duel.id})
    duel
  end

  def next_duel_phase!(duel, hero_id \\ nil) do
    updated = Duels.next_phase!(duel, hero_id)
    MobaWeb.broadcast("duel-#{duel.id}", "phase", updated.phase)
    updated
  end

  def finish_duel!(duel, winner, rewards), do: Duels.finish!(duel, winner, rewards)

  def duel_challenge(%{id: user_id}, %{id: opponent_id}) do
    attrs = %{user_id: user_id, opponent_id: opponent_id}

    MobaWeb.broadcast("user-#{user_id}", "challenge", attrs)
    MobaWeb.broadcast("user-#{opponent_id}", "challenge", attrs)
  end

  # QUESTS

  def track_pve_quests(hero), do: Quests.track_pve(hero)

  def active_quest_progression?(progressions), do: Enum.find(progressions, &is_nil(&1.completed_at))

  def last_completed_quest_progressions(hero), do: Quests.last_completed_progressions(hero)

  def list_quest_progressions(user_id, code \\ nil), do: Quests.list_progressions_by_code(user_id, code)

  def list_season_quest_progressions(user_id), do: Quests.list_season_progressions(user_id)

  def list_title_quest_progressions(user_id), do: Quests.list_title_progressions(user_id)

  def generate_daily_quest_progressions!(user_id \\ nil), do: Quests.generate_daily_progressions!(user_id)

  def list_daily_quest_progressions(user_id), do: Quests.list_progressions(user_id, true)
end
