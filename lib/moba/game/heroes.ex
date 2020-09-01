defmodule Moba.Game.Heroes do
  @moduledoc """
  Manages Hero records and queries.
  See Moba.Game.Schema.Hero for more info.
  """
  alias Moba.{Repo, Game}
  alias Game.Schema.Hero
  alias Game.Query.HeroQuery

  @pve_to_league_points Moba.redeem_pve_to_league_points_threshold()
  @pve_points_limit Moba.pve_points_limit()
  @max_level Moba.max_hero_level()
  @max_league_tier Moba.max_league_tier()

  # -------------------------------- PUBLIC API

  def get!(nil), do: nil

  def get!(id) do
    Hero
    |> Repo.get(id)
    |> base_preload()
  end

  def current(user_id, match_id) do
    Hero
    |> HeroQuery.by_user(user_id)
    |> HeroQuery.by_match(match_id)
    |> Repo.all()
  end

  def last_active_pve(user_id) do
    current_match = Game.current_match()

    HeroQuery.last_active_pve(user_id, current_match.id)
    |> Repo.all()
    |> List.first()
    |> base_preload()
  end

  def last_active_pvp(user_id) do
    HeroQuery.last_active_pvp(user_id)
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

  def create!(attrs, user, avatar, match) do
    %Hero{}
    |> Hero.create_changeset(attrs, user, avatar, match)
    |> Repo.insert!()
  end

  @doc """
  Creates a bot Hero, automatically leveling it and its skills.
  Level 0 bots exist to serve as weak targets for newly created player Heroes,
  and thus have their stats greatly reduced
  If a user is passed, the bot will be automatically assigned to PVP (Arena).
  """
  def create_bot!(avatar, level, difficulty, match, user \\ nil, league_tier \\ 0, pvp_points \\ 0) do
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
          pvp_last_picked: user && DateTime.utc_now()
        },
        user,
        avatar,
        match
      )

    if level > 0 do
      xp = Moba.xp_until_hero_level(level)

      bot
      |> add_experience(xp)
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
    |> add_experience(xp)
    |> max_league_updates()
  end

  def update_defender!(hero, updates), do: update!(hero, updates)

  @doc """
  A new PVP hero will start out with points inherited from its User and a clean score.
  To keep the same amount of Heroes in the Arena, the weakest PVP bot will be inactivated.
  """
  def prepare_for_pvp!(hero) do
    inactivate_weakest_pvp_bot()

    update!(hero, %{
      pvp_points: hero.user.pvp_points,
      pvp_ranking: nil,
      pvp_active: true,
      pvp_last_picked: Timex.now(),
      pvp_picks: hero.pvp_picks + 1,
      pvp_wins: 0,
      pvp_losses: 0,
      pvp_history: %{}
    })
  end

  @doc """
  Used for easy testing in development, unavailable in production
  """
  def level_cheat(hero) do
    xp = Moba.xp_to_next_hero_level(hero.level + 1)

    hero
    |> add_experience(xp)
    |> update!(%{pve_points: 24, gold: 99999, pve_battles_available: 1})
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
  def pvp_search(hero, sort \\ "level") do
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

  def pvp_search(%{pvp_points: pvp_points} = hero, filter, sort, page \\ 1) do
    HeroQuery.pvp_search(pvp_exclusions(hero), filter, pvp_points, sort, page)
    |> Repo.all()
    |> base_preload()
  end

  @doc """
  Retrieves top PVP ranked Heroes
  """
  def ranking(limit) do
    HeroQuery.pvp_ranked()
    |> HeroQuery.limit_by(limit)
    |> Repo.all()
    |> base_preload()
  end

  @doc """
  Retrieves PVP ranked Heroes by page
  """
  def paged_ranking(page) do
    HeroQuery.paged_ranking(page)
    |> Repo.all()
    |> base_preload()
  end

  @doc """
  Grabs all Heroes ordered by their pvp points and updates their ranking in the current match
  """
  def update_ranking! do
    HeroQuery.with_pvp_points()
    |> Repo.all()
    |> Enum.with_index(1)
    |> Enum.map(fn {hero, index} ->
      update!(hero, %{pvp_ranking: index})
    end)
  end

  @doc """
  Sets the Hero up for a League Challenge
  """
  def redeem_league!(%{pve_points: points} = hero) when points < @pve_points_limit, do: hero

  def redeem_league!(%{pve_points: points} = hero) do
    update!(hero, %{
      pve_points: points - @pve_to_league_points,
      league_step: 1
    })
  end

  def has_other_build?(hero) do
    builds =
      Repo.preload(hero, :builds)
      |> Map.get(:builds)

    length(builds) > 1
  end

  def pvp_targets_available(hero) do
    list = pvp_exclusions(hero)

    HeroQuery.pvp_active()
    |> HeroQuery.exclude(list)
    |> Repo.aggregate(:count)
  end

  # --------------------------------

  defp add_experience(hero, experience)
  defp add_experience(hero, nil), do: hero
  defp add_experience(%{level: level} = hero, _) when level >= @max_level, do: hero

  defp add_experience(hero, experience) do
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

  # when a Hero reaches the highest League, it gets leveled automatically to the max level
  defp level_to_max(%{level: current_level} = hero) when current_level < @max_level do
    diff = @max_level - current_level

    xp =
      Enum.reduce(1..diff, 0, fn level, acc ->
        acc + Moba.xp_to_next_hero_level(current_level + level)
      end)

    add_experience(hero, xp)
  end

  defp level_to_max(hero), do: hero

  defp inactivate_weakest_pvp_bot do
    HeroQuery.weakest_pvp_bot()
    |> Repo.all()
    |> List.first()
    |> update!(%{pvp_active: false})
  end

  defp base_preload(struct_or_structs, extras \\ []) do
    Repo.preload(
      struct_or_structs,
      [:user, :avatar, :items, active_build: [skills: Game.ordered_skills_query()]] ++ extras
    )
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

  defp max_league_updates(%{league_tier: tier} = hero) when tier == @max_league_tier, do: level_to_max(hero)
  defp max_league_updates(hero), do: hero
end
