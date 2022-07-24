defmodule Moba.Game.Heroes do
  @moduledoc """
  Manages Hero records and queries.
  See Moba.Game.Schema.Hero for more info.
  """
  alias Moba.{Repo, Game}
  alias Game.Schema.Hero
  alias Game.Query.HeroQuery

  # -------------------------------- PUBLIC API

  def buyback!(%{pve_state: "dead"} = hero) do
    price = buyback_price(hero)

    if hero.gold >= price do
      update!(hero, %{
        pve_state: "alive",
        buybacks: hero.buybacks + 1,
        gold: hero.gold - price,
        total_gold_farm: hero.total_gold_farm - price
      })
    else
      hero
    end
  end

  def buyback!(hero), do: hero

  def buyback_price(%{level: level}), do: level * Moba.buyback_multiplier()

  def can_shard_buyback?(hero), do: hero.pve_tier > 3 && hero.league_tier < Moba.master_league_tier()

  def collection_for(nil), do: []

  def collection_for(player_id) do
    HeroQuery.finished_pve()
    |> HeroQuery.load_avatar()
    |> HeroQuery.with_player(player_id)
    |> HeroQuery.unarchived()
    |> Repo.all()
    |> Enum.group_by(& &1.avatar.code)
    |> Enum.map(fn {code, heroes} ->
      {
        code,
        Enum.sort_by(heroes, &{&1.league_tier, total_farm(&1), !is_nil(&1.pve_ranking), &1.id}, :desc)
        |> List.first()
      }
    end)
    |> Enum.sort_by(fn {_code, hero} -> {hero.pve_ranking, hero.league_tier * -1} end, :asc)
    |> Enum.map(fn {code, hero} ->
      %{
        code: code,
        hero_id: hero.id,
        tier: hero.league_tier,
        avatar: hero.avatar,
        ranking: hero.pve_ranking,
        total_farm: total_farm(hero)
      }
    end)
  end

  def create!(attrs, player, avatar, skills, items \\ []) do
    avatar = Repo.preload(avatar, :ultimate)
    skills = [avatar.ultimate] ++ Enum.slice(skills, 0, 3)

    %Hero{}
    |> Hero.create_changeset(attrs, player, avatar, skills, items)
    |> Repo.insert!()
  end

  @doc """
  Creates a bot Hero, automatically leveling it and its skills.
  Level 0 bots exist to serve as weak targets for newly created player Heroes,
  and thus have their stats greatly reduced
  """
  def create_bot!(avatar, level, difficulty, league_tier, player \\ nil) do
    name = if player, do: player.bot_options.name, else: avatar.name
    finished_at = if player, do: Timex.now() |> Timex.shift(hours: 1), else: nil

    attrs = %{
      bot_difficulty: difficulty,
      name: name,
      gold: 100_000,
      league_tier: league_tier,
      total_gold_farm: bot_total_gold_farm(league_tier, difficulty),
      finished_at: finished_at
    }

    build_attrs = Map.put(attrs, :level, level)
    build = Game.generate_bot_build(build_attrs, avatar)
    attrs = Map.merge(attrs, %{item_order: build.item_order, skill_order: build.skill_order})
    bot = create!(attrs, player, avatar, build.skills, Enum.uniq_by(build.items, & &1.id))

    if level > 0 do
      xp = xp_until_hero_level(level)

      bot
      |> add_experience!(xp)
      |> level_up_skills()
    else
      bot
      |> update!(%{
        total_hp: bot.total_hp - avatar.hp_per_level * 3,
        total_mp: bot.total_mp - avatar.mp_per_level * 3,
        atk: bot.atk - avatar.atk_per_level * 3,
        level: 0
      })
    end
  end

  def finish_farming!(
        %{
          pve_farming_turns: farming_turns,
          pve_current_turns: current_turns,
          pve_farming_rewards: rewards,
          pve_farming_started_at: started,
          pve_state: state
        } = hero
      )
      when state in ["meditating", "mining"] do
    remaining_turns = zero_limit(current_turns - farming_turns)

    {hero, amount} = apply_farming_rewards(hero, farming_turns, state)

    new_reward = [%{state: state, started_at: started, turns: farming_turns, amount: amount}]

    hero
    |> Hero.replace_farming_rewards(rewards ++ new_reward)
    |> update!(%{
      pve_state: "alive",
      pve_farming_turns: 0,
      pve_farming_started_at: nil,
      pve_current_turns: remaining_turns
    })
  end

  def finish_farming!(hero), do: hero

  def get_hero!(nil), do: nil

  def get_hero!(id), do: HeroQuery.load() |> Repo.get!(id)

  @doc """
  Used for easy testing in development, unavailable in production
  """
  def level_cheat(hero) do
    xp = xp_to_next_hero_level(hero.level + 1)

    updated =
      hero
      |> add_experience!(xp)
      |> update!(%{gold: 100_000})

    if updated.level == 25 do
      update!(updated, %{league_tier: 5}) |> Game.generate_boss!()
    else
      updated
    end
  end

  def list_all_unfinished_heroes(player_id) do
    HeroQuery.latest(player_id, 100)
    |> HeroQuery.unfinished()
    |> Repo.all()
  end

  def list_all_finished_heroes(player_id) do
    HeroQuery.latest(player_id, 100)
    |> HeroQuery.finished()
    |> Repo.all()
  end

  def latest_unfinished_heroes(player_id) do
    HeroQuery.latest(player_id)
    |> HeroQuery.unfinished()
    |> Repo.all()
  end

  def latest_finished_heroes(player_id) do
    HeroQuery.latest(player_id)
    |> HeroQuery.finished()
    |> Repo.all()
  end

  def list_pickable_heroes(player_id, duel_inserted_at) do
    HeroQuery.pickable(player_id, duel_inserted_at)
    |> HeroQuery.load()
    |> Repo.all()
  end

  @doc """
  Retrieves top PVE ranked Heroes
  """
  def pve_ranking(limit) do
    HeroQuery.pve_ranked()
    |> HeroQuery.limit_by(limit)
    |> HeroQuery.load_avatar()
    |> Repo.all()
  end

  def community_pve_ranking do
    HeroQuery.pve_ranked()
    |> HeroQuery.limit_by(21)
    |> HeroQuery.load()
    |> Repo.all()
  end

  def prepare_league_challenge!(hero), do: update!(hero, %{league_step: 1})

  def set_skin!(hero, %{id: nil}), do: update!(hero, %{skin_id: nil}) |> Map.put(:skin, nil)
  def set_skin!(hero, skin), do: update!(hero, %{skin_id: skin.id}) |> Map.put(:skin, skin)

  def shard_buyback!(hero), do: update!(hero, %{pve_state: "alive"})

  def start_farming!(hero, state, turns) do
    update!(hero, %{pve_state: state, pve_farming_turns: turns, pve_farming_started_at: Timex.now()})
  end

  def update!(nil, _), do: nil

  def update!(hero, attrs, items \\ nil, skills \\ nil) do
    hero
    |> Hero.replace_items(items)
    |> Hero.replace_skills(skills)
    |> Hero.changeset(attrs)
    |> Repo.update!()
  end

  @doc """
  Only attackers are rewarded with XP in Training battles.
  """
  def update_attacker!(hero, updates) do
    {xp, updates} = Map.pop(updates, :total_xp)

    hero
    |> update!(updates)
    |> add_experience!(xp)
  end

  @doc """
  Grabs all Heroes ordered by their total_gold_farm and updates their pve_ranking
  """
  def update_pve_ranking! do
    Repo.update_all(Hero, set: [pve_ranking: nil])

    HeroQuery.non_bots()
    |> HeroQuery.finished_pve()
    |> HeroQuery.in_current_ranking_date()
    |> Repo.all()
    |> Enum.with_index(1)
    |> Enum.map(fn {hero, index} ->
      update!(hero, %{pve_ranking: index})
    end)
  end

  def xp_to_next_hero_level(level) when level < 1, do: 0
  def xp_to_next_hero_level(level), do: Moba.base_xp() + (level - 2) * Moba.xp_increment()

  # --------------------------------

  defp add_experience!(hero, nil), do: hero

  defp add_experience!(hero, experience) do
    hero
    |> Hero.changeset(%{experience: hero.experience + experience, total_xp_farm: hero.total_xp_farm + experience})
    |> check_if_leveled()
    |> Repo.update!()
  end

  defp apply_farming_rewards(hero, turns, "meditating") do
    rewards = turns * Enum.random(Moba.farm_per_turn(hero.pve_tier))
    hero = add_experience!(hero, rewards)

    {hero, rewards}
  end

  defp apply_farming_rewards(hero, turns, "mining") do
    rewards = turns * Enum.random(Moba.farm_per_turn(hero.pve_tier))
    hero = update!(hero, %{gold: hero.gold + rewards, total_gold_farm: hero.total_gold_farm + rewards})

    {hero, rewards}
  end

  defp bot_total_gold_farm(league_tier, difficulty) do
    base = bot_total_gold_farm_base(league_tier, difficulty)
    extra_farm = zero_limit(league_tier - 3)

    range =
      case difficulty do
        # 0..800
        "weak" -> 0..2
        # 800..1600
        "moderate" -> 2..4
        # 1600..3200
        "strong" -> (4 + extra_farm)..(6 + extra_farm)
        # 19_200..24_000
        "pvp_master" -> 0..12
        # 26_400..30_000
        "pvp_grandmaster" -> 6..15
      end

    base + 400 * Enum.random(range)
  end

  defp bot_total_gold_farm_base(tier, difficulty) when difficulty in ["pvp_master", "pvp_grandmaster"],
    do: (tier - 1) * 4800

  defp bot_total_gold_farm_base(tier, _), do: tier * 4800

  defp check_if_leveled(%{data: data, changes: changes} = changeset) do
    level = changes[:level] || data.level
    xp = changes[:experience] || 0
    diff = xp_to_next_hero_level(level + 1) - xp

    if diff <= 0 do
      changeset
      |> Hero.level_up(level, diff * -1)
      |> check_if_leveled()
    else
      changeset
    end
  end

  # randomly levels up skills for a bot
  defp level_up_skills(hero) do
    ultimate = Enum.find(hero.skills, fn skill -> skill.ultimate end)
    hero = Enum.reduce(1..3, hero, fn _, acc -> Game.level_up_skill!(acc, ultimate.code) end)

    Enum.reduce(1..100, hero, fn _, acc ->
      skill = Enum.shuffle(acc.skills) |> List.first()
      Game.level_up_skill!(acc, skill.code)
    end)
  end

  defp total_farm(hero), do: hero.total_gold_farm + hero.total_xp_farm

  defp xp_until_hero_level(level) when level < 2, do: 0
  defp xp_until_hero_level(level), do: xp_to_next_hero_level(level) + xp_until_hero_level(level - 1)

  defp zero_limit(total) when total < 0, do: 0
  defp zero_limit(total), do: total
end
