defmodule Moba.Game do
  @moduledoc """
  Top-level domain of all gameplay logic

  As a top-level domain, it can access its siblings like Engine and Accounts, its parent (Moba)
  and all of its children (Heroes, Matches, etc). It cannot, however, access children of its
  siblings.
  """

  alias Moba.{Repo, Game, Accounts}
  alias Game.{Heroes, Matches, Leagues, Targets, Items, Skills, Avatars, Builds, ArenaPicks, Skins, Duels}

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

  def last_pvp_hero(user_id), do: Heroes.last_active_pvp(user_id)

  def latest_heroes(user_id), do: Heroes.list_latest(user_id)

  def eligible_heroes_for_pvp(user_id), do: Heroes.list_pvp_eligible(user_id)

  @doc """
  Orchestrates the creation of a Hero, which involves creating its initial build, activating it
  and generating its first Jungle targets
  """
  def create_hero!(attrs, user, avatar, skills, match \\ current_match()) do
    attrs =
      if Map.get(attrs, :easy_mode) do
        Map.merge(attrs, %{pve_battles_available: 1000})
      else
        attrs
      end

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

  def create_pvp_bot_hero!(user, avatar, match) do
    difficulty = if user.bot_tier == Moba.master_league_tier(), do: "master", else: "grandmaster"
    Heroes.create_bot!(avatar, 25, difficulty, match, user, 0, user.bot_tier)
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

  def summon_hero!(user, avatar, skills, items) do
    if user.shard_count >= Moba.summon_cost() do
      hero =
        create_hero!(
          %{
            name: user.username,
            league_tier: Moba.master_league_tier(),
            gold: Moba.summon_total_gold(),
            pve_battles_available: 0,
            finished_pve: true,
            summoned: true
          },
          user,
          avatar,
          skills,
          Game.current_match()
        )

      Enum.reduce(items, hero, fn item, acc ->
        buy_item!(acc, item)
      end)
      |> Heroes.level_to_max!()
      |> level_active_build_to_max!()

      Accounts.update_user!(user, %{shard_count: user.shard_count - Moba.summon_cost()})
    else
      user
    end
  end

  def master_league?(%{league_tier: tier}), do: tier == Moba.master_league_tier()
  def max_league?(%{league_tier: tier}), do: tier == Moba.max_league_tier()

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

  def redeem_league!(hero), do: Heroes.redeem_league!(hero)

  def level_cheat(hero), do: Heroes.level_cheat(hero)

  def hero_has_other_build?(hero), do: Heroes.has_other_build?(hero)

  def pvp_targets_available(hero), do: Heroes.pvp_targets_available(hero)

  def set_hero_skin!(hero, skin), do: Heroes.set_skin!(hero, skin)

  def veteran_hero?(%{easy_mode: true}), do: false
  def veteran_hero?(_), do: true

  def maybe_generate_boss(%{pve_battles_available: 0, boss_id: nil, pve_points: points} = hero) do
    if master_league?(hero) && points == Moba.pve_points_limit() do
      generate_boss!(hero)
    else
      hero
    end
  end

  def maybe_generate_boss(hero), do: hero

  def maybe_finish_pve(%{pve_battles_available: 0, pve_points: points, boss_id: nil, finished_pve: false} = hero) do
    if max_league?(hero) || points < Moba.pve_points_limit() do
      finish_pve!(hero)
    else
      hero
    end
  end

  def maybe_finish_pve(hero), do: hero

  def finish_pve!(%{finished_pve: false} = hero) do
    hero = Repo.preload(hero, :user)
    shards = Accounts.pve_shards_for(hero.user, hero.league_tier)
    updated = update_hero!(hero, %{finished_pve: true, shards_reward: shards})

    collection = Heroes.collection_for(updated.user_id)
    Accounts.finish_pve!(updated.user, collection, shards)
    updated
  end

  def finish_pve!(hero), do: hero

  def generate_boss!(hero) do
    boss =
      Heroes.create!(
        %{name: "Roshan", league_tier: 6, level: 25, bot_difficulty: "boss", boss_id: hero.id},
        nil,
        Avatars.boss!(),
        current_match()
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
    update_hero!(hero, %{dead: true})
  end

  def finalize_boss!(_, _, hero), do: update_hero!(hero, %{boss_id: nil, pve_points: Moba.pve_points_limit() - 1})

  defdelegate buyback!(hero), to: Heroes
  defdelegate buyback_price(hero), to: Heroes

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
end
