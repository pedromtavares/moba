defmodule Moba.Game.Heroes do
  @moduledoc """
  Manages Hero records and queries.
  See Moba.Game.Schema.Hero for more info.
  """
  alias Moba.{Repo, Game}
  alias Game.Schema.Hero
  alias Game.Query.{HeroQuery, SkillQuery}

  # -------------------------------- PUBLIC API

  def get!(nil), do: nil

  def get!(id) do
    Hero
    |> Repo.get(id)
    |> base_preload()
  end

  def pvp_last_picked(user_id) do
    HeroQuery.pvp_last_picked(user_id)
    |> Repo.all()
    |> List.first()
    |> base_preload()
  end

  def list_latest(user_id) do
    HeroQuery.latest(user_id)
    |> Repo.all()
    |> base_preload()
  end

  def list_pvp_eligible(user_id) do
    HeroQuery.eligible_for_pvp(user_id)
    |> Repo.all()
    |> base_preload()
  end

  def create!(attrs, user, avatar) do
    %Hero{}
    |> Hero.create_changeset(attrs, user, avatar)
    |> Repo.insert!()
  end

  @doc """
  Creates a bot Hero, automatically leveling it and its skills.
  Level 0 bots exist to serve as weak targets for newly created player Heroes,
  and thus have their stats greatly reduced
  If a user is passed, the bot will be automatically assigned to PVP (Arena).
  """
  def create_bot!(avatar, level, difficulty, user \\ nil, pvp_points \\ 0, league_tier \\ 0) do
    name = if user, do: user.username, else: avatar.name

    bot =
      create!(
        %{
          bot_difficulty: difficulty,
          name: name,
          pvp_points: pvp_points,
          gold: 100_000,
          pvp_active: user != nil,
          league_tier: league_tier,
          total_gold_farm: bot_total_gold_farm(league_tier, difficulty),
          pvp_last_picked: user && DateTime.utc_now()
        },
        user,
        avatar
      )

    if level > 0 do
      xp = Moba.xp_until_hero_level(level)

      bot
      |> add_experience!(xp)
      |> Game.generate_bot_build!()
      |> level_up_skills()
    else
      bot
      |> Game.generate_bot_build!()
      |> update!(%{
        total_hp: bot.total_hp - avatar.hp_per_level * 3,
        total_mp: bot.total_mp - avatar.mp_per_level * 3,
        atk: bot.atk - avatar.atk_per_level * 3,
        level: 0
      })
    end
  end

  def update!(nil, _), do: nil

  def update!(hero, attrs, items \\ nil) do
    hero = if items, do: Repo.preload(hero, :items), else: hero

    hero
    |> Hero.replace_items(items)
    |> Hero.changeset(attrs)
    |> Repo.update!()
  end

  @doc """
  Only attackers are rewarded with XP in PVE (Jungle) battles.
  If they happen to reach the max league (Master), they are
  automatically pushed to level 25 (max level).
  """
  def update_attacker!(hero, updates) do
    {xp, updates} = Map.pop(updates, :total_xp)

    hero
    |> update!(updates)
    |> add_experience!(xp)
  end

  @doc """
  A new PVP hero will start out with points inherited from its User and a clean score.
  To keep the same amount of Heroes in the Arena, the weakest PVP bot will be inactivated.
  """
  def prepare_for_pvp!(hero) do
    inactivate_weakest_pvp_bot(hero.league_tier)

    update!(hero, %{
      pvp_points: 0,
      pvp_ranking: nil,
      pvp_active: true,
      pvp_last_picked: Timex.now(),
      pvp_picks: hero.pvp_picks + 1,
      pvp_wins: 0,
      pvp_losses: 0,
      pvp_history: %{},
      match_id: Game.current_match().id
    })
  end

  @doc """
  Used for easy testing in development, unavailable in production
  """
  def level_cheat(hero) do
    xp = Moba.xp_to_next_hero_level(hero.level + 1)

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

  def pve_win_rate(hero) do
    sum = hero.wins + hero.ties + hero.losses

    if sum > 0 do
      round(hero.wins * 100 / sum)
    else
      0
    end
  end

  def pvp_win_rate(hero) do
    sum = hero.pvp_wins + hero.pvp_losses

    if sum > 0 do
      round(hero.pvp_wins * 100 / sum)
    else
      0
    end
  end

  @doc """
  Returns valid PVP targets for a Hero, prioritizing ones with equivalent points
  """
  def pvp_search(hero, sort \\ "hp") do
    ["normal", "easy", "hard", "hardest", nil]
    |> Enum.reduce_while([], fn filter, _ ->
      results = pvp_search(hero, filter, sort)

      if Enum.count(results) > 0 do
        {:halt, {filter, results}}
      else
        {:cont, {filter, results}}
      end
    end)
  end

  def pvp_search(%{pvp_points: pvp_points, league_tier: league_tier} = hero, filter, sort, page \\ 1) do
    HeroQuery.pvp_search(pvp_exclusions(hero), filter, pvp_points, league_tier, sort, page)
    |> Repo.all()
    |> base_preload()
  end

  @doc """
  Retrieves top PVP ranked Heroes
  """
  def pvp_ranking(league_tier, limit) do
    HeroQuery.pvp_ranked()
    |> HeroQuery.with_league_tier(league_tier)
    |> HeroQuery.limit_by(limit)
    |> Repo.all()
    |> base_preload()
  end

  @doc """
  Retrieves PVP ranked Heroes by page
  """
  def paged_pvp_ranking(league_tier, page) do
    HeroQuery.paged_pvp_ranking(page)
    |> HeroQuery.with_league_tier(league_tier)
    |> Repo.all()
    |> base_preload()
  end

  @doc """
  Grabs all Heroes ordered by their pvp points and updates their pvp_ranking in the current Arena match
  """
  def update_pvp_ranking!(league_tier) do
    HeroQuery.with_pvp_points()
    |> HeroQuery.load_avatar()
    |> HeroQuery.with_league_tier(league_tier)
    |> Repo.all()
    |> Enum.with_index(1)
    |> Enum.map(fn {hero, index} ->
      update!(hero, %{pvp_ranking: index})
    end)
  end

  @doc """
  Grabs heroes with pve_rankings close to the target hero
  """
  def pve_search(%{pve_ranking: ranking}) when not is_nil(ranking) do
    {min, max} =
      if ranking <= 3 do
        {1, 5}
      else
        {ranking - 2, ranking + 2}
      end

    HeroQuery.non_bots()
    |> HeroQuery.by_pve_ranking(min, max)
    |> Repo.all()
    |> avatar_preload()
  end

  def pve_search(%{total_gold_farm: total_gold_farm, bot_difficulty: bot}) when not is_nil(bot) do
    HeroQuery.non_bots()
    |> HeroQuery.by_total_gold_farm(total_gold_farm - 200, total_gold_farm + 200)
    |> HeroQuery.limit_by(5)
    |> Repo.all()
    |> avatar_preload()
  end

  def pve_search(%{total_gold_farm: total_gold_farm, id: id}) do
    by_farm =
      HeroQuery.non_bots()
      |> HeroQuery.by_total_gold_farm(total_gold_farm - 500, total_gold_farm + 500)
      |> Repo.all()
      |> avatar_preload()

    hero_index = Enum.find_index(by_farm, &(&1.id == id))

    by_farm
    |> Enum.with_index()
    |> Enum.filter(fn {_, index} ->
      index >= hero_index - 2 && index <= hero_index + 2
    end)
    |> Enum.map(fn {elem, _} -> elem end)
  end

  @doc """
  Retrieves top PVE ranked Heroes
  """
  def pve_ranking(limit) do
    HeroQuery.pve_ranked()
    |> HeroQuery.limit_by(limit)
    |> Repo.all()
    |> base_preload()
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

  def prepare_league_challenge!(hero), do: update!(hero, %{league_step: 1})

  def has_other_build?(hero) do
    builds =
      Repo.preload(hero, :builds)
      |> Map.get(:builds)

    length(builds) > 1
  end

  def pvp_targets_available(hero) do
    list = pvp_exclusions(hero)

    HeroQuery.pvp_active()
    |> HeroQuery.exclude_ids(list)
    |> HeroQuery.with_league_tier(hero.league_tier)
    |> Repo.aggregate(:count)
  end

  def collection_for(user_id) do
    HeroQuery.finished_pve()
    |> HeroQuery.with_user(user_id)
    |> HeroQuery.unarchived()
    |> Repo.all()
    |> Repo.preload(:avatar)
    |> Enum.group_by(& &1.avatar.code)
    |> Enum.map(fn {code, heroes} ->
      {
        code,
        Enum.sort_by(heroes, &{&1.pve_ranking, &1.league_tier, &1.total_gold_farm}, :desc) |> List.first()
      }
    end)
    |> Enum.sort_by(fn {_code, hero} -> {hero.league_tier, hero.total_gold_farm} end, :desc)
    |> Enum.map(fn {code, hero} -> %{code: code, hero_id: hero.id, tier: hero.league_tier, avatar: hero.avatar} end)
  end

  def set_skin!(hero, %{id: nil}), do: update!(hero, %{skin_id: nil}) |> Map.put(:skin, nil)
  def set_skin!(hero, skin), do: update!(hero, %{skin_id: skin.id}) |> Map.put(:skin, skin)

  def buyback_price(%{level: level}), do: level * Moba.buyback_multiplier()

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

  def start_farming!(hero, state, turns) do
    update!(hero, %{pve_state: state, pve_farming_turns: turns, pve_farming_started_at: Timex.now()})
  end

  def finish_farming!(
        %{
          pve_farming_turns: farming_turns,
          pve_current_turns: current_turns,
          pve_farming_rewards: rewards,
          pve_farming_started_at: started,
          pve_state: state
        } = hero
      ) do
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

  # --------------------------------

  defp add_experience!(hero, nil), do: hero

  defp add_experience!(hero, experience) do
    hero = Repo.preload(hero, :user)
    if hero.user, do: Moba.add_user_experience(hero.user, experience)

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

  defp check_if_leveled(%{data: data, changes: changes} = changeset) do
    level = changes[:level] || data.level
    xp = changes[:experience] || 0
    diff = Moba.xp_to_next_hero_level(level + 1) - xp

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
    hero = Repo.preload(hero, active_build: [:skills])
    ultimate = Enum.find(hero.active_build.skills, fn skill -> skill.ultimate end)
    hero = Enum.reduce(1..3, hero, fn _, acc -> Game.level_up_skill!(acc, ultimate.code) end)

    Enum.reduce(1..100, hero, fn _, acc ->
      skill = Enum.shuffle(acc.active_build.skills) |> List.first()
      Game.level_up_skill!(acc, skill.code)
    end)
  end

  defp bot_total_gold_farm(league_tier, difficulty) do
    base = bot_total_gold_farm_base(league_tier, difficulty)

    range =
      case difficulty do
        # 0..800
        "weak" -> 0..2
        # 1200..2000
        "moderate" -> 2..4
        "strong" -> (4 + league_tier)..(6 + league_tier)
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

  defp inactivate_weakest_pvp_bot(league_tier) do
    HeroQuery.weakest_pvp_bot(league_tier)
    |> Repo.all()
    |> List.first()
    |> update!(%{pvp_active: false})
  end

  defp base_preload(struct_or_structs, extras \\ []) do
    Repo.preload(
      struct_or_structs,
      [:user, :avatar, :items, :skin, active_build: [skills: SkillQuery.ordered()]] ++ extras
    )
  end

  defp avatar_preload(struct_or_structs) do
    Repo.preload(struct_or_structs, :avatar)
  end

  # makes sure Heroes that were recently battled are excluded from searches
  defp pvp_exclusions(%{id: hero_id, pvp_history: history}) do
    [hero_id] ++
      Enum.reduce(history, [], fn {id, time}, acc ->
        parsed = Timex.parse!(time, "{ISO:Extended:Z}")

        if Timex.before?(parsed, Timex.now()) do
          acc
        else
          acc ++ [id]
        end
      end)
  end

  defp zero_limit(total) when total < 0, do: 0
  defp zero_limit(total), do: total
end
