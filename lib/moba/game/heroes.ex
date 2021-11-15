defmodule Moba.Game.Heroes do
  @moduledoc """
  Manages Hero records and queries.
  See Moba.Game.Schema.Hero for more info.
  """
  alias Moba.{Repo, Game}
  alias Game.Schema.Hero
  alias Game.Query.{HeroQuery, SkillQuery}

  @pve_points_limit Moba.pve_points_limit()
  @max_level Moba.max_hero_level()
  @master_league_tier Moba.master_league_tier()

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
          total_farm: bot_total_farm(level, difficulty),
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

  def level_to_max!(%{level: current_level} = hero) when current_level < @max_level do
    diff = @max_level - current_level

    xp =
      Enum.reduce(1..diff, 0, fn level, acc ->
        acc + Moba.xp_to_next_hero_level(current_level + level)
      end)

    add_experience!(hero, xp)
  end

  def level_to_max!(hero), do: hero

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
    |> master_league_updates()
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
      |> update!(%{
        pve_points: Moba.pve_points_limit(),
        gold: 100_000,
        pve_battles_available: 2,
        buffed_battles_available: 0
      })

    # |> Game.generate_boss!()

    if updated.level == 25 do
      update!(updated, %{league_tier: 5}) |> master_league_updates() |> Game.level_active_build_to_max!()
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

  def pve_search(%{total_farm: total_farm, bot_difficulty: bot}) when not is_nil(bot) do
    HeroQuery.non_bots()
    |> HeroQuery.by_total_farm(total_farm - 200, total_farm + 200)
    |> HeroQuery.limit_by(5)
    |> Repo.all()
    |> avatar_preload()
  end

  def pve_search(%{total_farm: total_farm, id: id}) do
    by_farm =
      HeroQuery.non_bots()
      |> HeroQuery.by_total_farm(total_farm - 500, total_farm + 500)
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
  Grabs all Heroes ordered by their total_farm and updates their pve_ranking
  """
  def update_pve_ranking! do
    Repo.update_all(Hero, set: [pve_ranking: nil])

    HeroQuery.non_bots()
    |> HeroQuery.finished_pve()
    |> HeroQuery.non_summoned()
    |> HeroQuery.in_current_ranking_date()
    |> Repo.all()
    |> Enum.with_index(1)
    |> Enum.map(fn {hero, index} ->
      update!(hero, %{pve_ranking: index})
    end)
  end

  @doc """
  Sets the Hero up for a League Challenge
  """
  def redeem_league!(%{pve_points: points} = hero) when points < @pve_points_limit, do: hero

  def redeem_league!(%{league_tier: @master_league_tier} = hero), do: update!(hero, %{league_step: 1})

  def redeem_league!(hero), do: update!(hero, %{pve_points: 0, league_step: 1})

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
    |> Repo.all()
    |> Repo.preload(:avatar)
    |> Enum.group_by(& &1.avatar.code)
    |> Enum.map(fn {code, heroes} ->
      {
        code,
        Enum.sort_by(heroes, &{&1.pve_ranking, &1.league_tier, &1.total_farm}, :desc) |> List.first()
      }
    end)
    |> Enum.sort_by(fn {_code, hero} -> {hero.league_tier, hero.total_farm} end, :desc)
    |> Enum.map(fn {code, hero} -> %{code: code, hero_id: hero.id, tier: hero.league_tier, avatar: hero.avatar} end)
  end

  def set_skin!(hero, %{id: nil}), do: update!(hero, %{skin_id: nil}) |> Map.put(:skin, nil)
  def set_skin!(hero, skin), do: update!(hero, %{skin_id: skin.id}) |> Map.put(:skin, skin)

  def buyback_price(%{level: level, user: user}), do: level * Moba.buyback_multiplier(user)

  def buyback!(%{dead: true} = hero) do
    price = buyback_price(hero)

    if hero.gold >= price do
      update!(hero, %{
        dead: false,
        buybacks: hero.buybacks + 1,
        gold: hero.gold - price,
        total_farm: hero.total_farm - price
      })
    else
      hero
    end
  end

  def buyback!(hero), do: hero

  # --------------------------------

  defp add_experience!(hero, experience)
  defp add_experience!(hero, nil), do: hero
  defp add_experience!(%{level: level} = hero, _) when level >= @max_level, do: hero

  defp add_experience!(hero, experience) do
    hero = Repo.preload(hero, :user)
    if hero.user, do: Moba.add_user_experience(hero.user, experience)

    hero
    |> Hero.changeset(%{experience: hero.experience + experience})
    |> check_if_leveled()
    |> Repo.update!()
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

  defp bot_total_farm(level, _) when level > 25, do: 30_000

  defp bot_total_farm(_, "master"), do: Enum.random(18_000..23_000)

  defp bot_total_farm(_, "grandmaster"), do: Enum.random(27_000..30_000)

  defp bot_total_farm(level, difficulty) do
    base = Moba.xp_until_hero_level(level)

    extra =
      case difficulty do
        "weak" -> 1000
        "moderate" -> 2000
        "strong" -> 4000
      end

    league_bonus = Game.league_tier_for(level) * Moba.league_win_gold_bonus()

    base + extra + league_bonus
  end

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

  defp master_league_updates(%{league_tier: tier, easy_mode: true} = hero) when tier == @master_league_tier do
    master_league_updates(%{hero | easy_mode: false})
    |> Game.finish_pve!()
  end

  defp master_league_updates(%{league_tier: tier, level: level} = hero)
       when tier == @master_league_tier and level < @max_level do
    hero
    |> level_to_max!()
    |> Game.level_active_build_to_max!()
  end

  defp master_league_updates(hero), do: hero
end
