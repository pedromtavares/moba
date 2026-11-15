defmodule Moba.Game.Heroes do
  @moduledoc """
  Manages Hero records and queries.
  See Moba.Game.Schema.Hero for more info.
  """
  alias Moba.{Repo, Game}
  alias Game.Schema.Hero
  alias Game.Query.HeroQuery
  import Ecto.Query, only: [from: 2]

  # -------------------------------- PUBLIC API

  def best_hero_rank(player_id) do
    from(h in Hero, where: h.player_id == ^player_id and h.pve_ranking > 0, select: min(h.pve_ranking))
    |> Repo.one()
  end

  def available_hero?(hero) do
    ago = Timex.shift(Timex.now(), days: -Moba.available_hero_days()) |> Timex.to_datetime()

    DateTime.compare(hero.finished_at, ago) == :lt
  end

  def available_pvp_heroes(player, excluded_hero_ids \\ []) do
    trained_pvp_heroes(player.id, excluded_hero_ids, 21) ++ pvp_bots(3)
  end

  def available_top_heroes do
    HeroQuery.load()
    |> HeroQuery.pve_ranked()
    |> HeroQuery.finished_before()
    |> HeroQuery.with_max_league_tier()
    |> HeroQuery.limit_by(100)
    |> Repo.all()
  end

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
    query = HeroQuery.finished_pve() |> HeroQuery.with_player(player_id) |> HeroQuery.unarchived()

    heroes =
      from(hero in query, order_by: [asc_nulls_last: hero.pve_ranking, asc: hero.id], preload: :avatar)
      |> Repo.all()

    profile_picks =
      heroes
      |> Enum.uniq_by(& &1.avatar.code)
      |> Enum.with_index()
      |> Map.new(fn {hero, position} ->
        entry = collection_entry(hero)
        avatar = Map.take(entry.avatar, [:code, :image])
        {entry.code, %{entry | avatar: avatar} |> Map.put(:position, position)}
      end)

    heroes
    |> Enum.group_by(& &1.avatar.code)
    |> Enum.map(fn {code, heroes} ->
      {code, Enum.min_by(heroes, &{is_nil(&1.pve_ranking), &1.pve_ranking, &1.id})}
    end)
    |> Enum.sort_by(fn {_code, hero} -> {hero.pve_ranking, hero.league_tier * -1} end, :asc)
    |> Enum.map(fn {code, hero} -> Map.put(collection_entry(hero), :profile, Map.fetch!(profile_picks, code)) end)
  end

  def perfect_collection_codes(nil), do: MapSet.new()

  def perfect_collection_codes(player_id) do
    query = perfect_collection_heroes(HeroQuery.finished(Hero), [player_id])

    from([_hero, avatar] in query, distinct: true, select: avatar.code)
    |> Repo.all()
    |> MapSet.new()
  end

  def profile_collection(player, perfect_picks) do
    (player.hero_collection || [])
    |> Enum.map(fn entry ->
      entry
      |> Map.get("profile", entry)
      |> Map.put("avatar_name", get_in(entry, ["avatar", "name"]))
      |> Map.merge(Map.get(perfect_picks, entry["code"], %{}))
    end)
    |> Enum.sort_by(&{!Map.has_key?(perfect_picks, &1["code"]), &1["position"]})
  end

  def profile_featured_hero(player, collection) do
    profile_featured_heroes([{player, collection}], HeroQuery.load())[player.id]
  end

  def profile_featured_heroes(players_with_collections, query) do
    choices =
      for {player, collection} <- players_with_collections, into: %{} do
        saved_id = Map.get(player.preferences || %{}, :featured_hero_id)
        collection_id = List.first(collection, %{})["hero_id"]
        {player.id, Enum.reject([saved_id, collection_id, player.current_pve_hero_id], &is_nil/1)}
      end

    hero_ids = choices |> Map.values() |> List.flatten() |> Enum.uniq()

    heroes =
      if hero_ids == [] do
        %{}
      else
        query |> HeroQuery.with_ids(hero_ids) |> HeroQuery.unarchived() |> Repo.all() |> Map.new(&{&1.id, &1})
      end

    for {player_id, ids} <- choices, into: %{} do
      hero =
        Enum.find_value(ids, fn id ->
          case heroes[id] do
            %{player_id: ^player_id} = hero -> hero
            _ -> nil
          end
        end)

      {player_id, hero}
    end
  end

  def perfect_profile_picks(player_id) do
    Map.get(perfect_profile_picks_for_players([player_id]), player_id, %{})
  end

  def perfect_profile_picks_for_players([]), do: %{}

  def perfect_profile_picks_for_players(player_ids) do
    query = perfect_collection_heroes(HeroQuery.finished_pve(), player_ids)

    from([hero, avatar] in query,
      distinct: [hero.player_id, avatar.code],
      order_by: [asc_nulls_last: hero.pve_ranking, asc: hero.id],
      select: {
        hero.player_id,
        avatar.code,
        %{
          "hero_id" => hero.id,
          "tier" => hero.league_tier,
          "total_farm" => hero.total_xp_farm + hero.total_gold_farm,
          "avatar" => %{"code" => avatar.code, "image" => avatar.image},
          "avatar_name" => avatar.name
        }
      }
    )
    |> Repo.all()
    |> Enum.reduce(%{}, fn {player_id, code, pick}, picks ->
      Map.update(picks, player_id, %{code => pick}, &Map.put(&1, code, pick))
    end)
  end

  defp perfect_collection_heroes(query, player_ids) do
    grandmaster = Moba.max_league_tier()
    solo_farm = Moba.max_total_farm()
    team_farm = 3 * solo_farm

    from(hero in query,
      join: avatar in assoc(hero, :avatar),
      left_join: team in assoc(hero, :training_team),
      where: hero.player_id in ^player_ids and is_nil(hero.archived_at),
      where:
        (is_nil(hero.training_team_id) and hero.league_tier == ^grandmaster and
           hero.total_xp_farm + hero.total_gold_farm >= ^solo_farm) or
          (team.player_id == hero.player_id and team.phase == "finished" and not is_nil(team.finished_at) and
             team.league_tier == ^grandmaster and team.total_farm >= ^team_farm and
             fragment("cardinality(?) = 3 AND ? = ANY(?)", team.hero_ids, hero.id, team.hero_ids))
    )
  end

  defp collection_entry(hero) do
    %{
      code: hero.avatar.code,
      hero_id: hero.id,
      tier: hero.league_tier,
      avatar: hero.avatar,
      total_farm: total_farm(hero)
    }
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
  def create_bot!(avatar, level, difficulty, league_tier) do
    pvp? = Enum.member?(["pvp_master", "pvp_grandmaster"], difficulty)
    name = if pvp?, do: Faker.Superhero.name(), else: avatar.name

    attrs = %{
      bot_difficulty: difficulty,
      name: name,
      gold: 100_000,
      league_tier: league_tier,
      total_gold_farm: bot_total_gold_farm(league_tier, difficulty)
    }

    build_attrs = Map.put(attrs, :level, level)
    build = Game.generate_bot_build(build_attrs, avatar)
    attrs = Map.merge(attrs, %{item_order: build.item_order, skill_order: build.skill_order})

    items = Enum.uniq_by(build.items, & &1.id)
    attrs = if pvp?, do: Map.merge(attrs, Game.item_attributes(items)), else: attrs
    bot = create!(attrs, nil, avatar, build.skills, items)

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

  @doc "Claims a completed farming session once, returning {hero, claimed?}."
  def claim_farming!(hero) do
    {:ok, result} =
      Repo.transaction(fn ->
        Repo.one!(from h in Hero, where: h.id == ^hero.id, lock: "FOR UPDATE")
        stored = get_hero!(hero.id)

        if stored.pve_state in ["meditating", "mining"] &&
             is_integer(stored.pve_farming_turns) && stored.pve_farming_turns > 0 &&
             stored.pve_farming_turns <= stored.pve_current_turns && stored.pve_farming_started_at &&
             DateTime.diff(DateTime.utc_now(), stored.pve_farming_started_at) >=
               stored.pve_farming_turns * Moba.seconds_per_turn() do
          {complete_farming!(stored), true}
        else
          {stored, false}
        end
      end)

    result
  end

  defp complete_farming!(
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

  def get_hero!(nil), do: nil

  def get_hero!(id), do: HeroQuery.load() |> Repo.get!(id)

  def get_heroes([]), do: []
  def get_heroes(hero_ids), do: HeroQuery.with_ids(HeroQuery.load(), hero_ids) |> Repo.all()

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

  def list_solo_training(scope, status, limit \\ Moba.base_hero_count(), offset \\ 0, avatar_code \\ nil) do
    query = HeroQuery.latest(scope.player_id, limit) |> owned_training(scope) |> HeroQuery.solo()
    query = if avatar_code, do: for_avatar(query, avatar_code), else: query
    query = if status == "finished", do: HeroQuery.finished(query), else: HeroQuery.unfinished(query)
    from(hero in query, order_by: [desc: hero.id], offset: ^offset) |> Repo.all()
  end

  def get_finished_avatar_hero(scope, id, avatar_code) do
    Hero
    |> HeroQuery.with_player(scope.player_id)
    |> HeroQuery.unarchived()
    |> HeroQuery.finished()
    |> owned_training(scope)
    |> for_avatar(avatar_code)
    |> Repo.get(id)
  end

  defp owned_training(query, %{user: %{id: user_id}}) do
    from h in query, join: p in assoc(h, :player), where: p.user_id == ^user_id
  end

  defp owned_training(query, %{user: nil}) do
    from h in query, join: p in assoc(h, :player), where: is_nil(p.user_id)
  end

  defp for_avatar(query, avatar_code) do
    from h in query, join: a in assoc(h, :avatar), where: a.code == ^avatar_code
  end

  def latest_finished_heroes(player_id) do
    HeroQuery.latest(player_id)
    |> HeroQuery.finished()
    |> Repo.all()
  end

  def max_farm?(hero) do
    hero.total_gold_farm + hero.total_xp_farm == Moba.max_total_farm()
  end

  @doc """
  Retrieves top PVE ranked Heroes
  """
  def pve_ranking(limit) do
    HeroQuery.pve_ranked()
    |> HeroQuery.limit_by(limit)
    |> HeroQuery.load()
    |> Repo.all()
  end

  def league_ranking(hero, limit \\ Moba.pve_ranking_limit())

  def league_ranking(%{league_tier: tier}, _limit) when tier < 2 do
    %{entries: [], position: nil, total: 0}
  end

  def league_ranking(%{id: hero_id, league_tier: tier}, limit) do
    eligible =
      HeroQuery.non_bots()
      |> HeroQuery.solo()
      |> HeroQuery.finished()

    ranked =
      from(h in eligible,
        where: h.league_tier == ^tier,
        windows: [
          league: [
            order_by: [
              desc: fragment("? + ?", h.total_xp_farm, h.total_gold_farm),
              asc: fragment("? - ?", h.finished_at, h.inserted_at),
              asc: h.id
            ]
          ]
        ],
        select: %{id: h.id, position: over(row_number(), :league), total: over(count(), [])}
      )

    entries =
      Repo.all(
        from(h in Hero,
          join: r in subquery(ranked),
          on: r.id == h.id,
          where: r.position <= ^limit or h.id == ^hero_id,
          order_by: r.position,
          preload: [:avatar, :skin],
          select: %{hero: h, position: r.position, total: r.total}
        )
      )

    current = Enum.find(entries, &(&1.hero.id == hero_id))

    %{
      entries: Enum.filter(entries, &(&1.position <= limit)),
      position: current && current.position,
      total:
        case entries do
          [entry | _] -> entry.total
          [] -> 0
        end
    }
  end

  def pvp_bots(limit \\ 5) do
    HeroQuery.pvp_bots("pvp_grandmaster", Moba.max_league_tier())
    |> HeroQuery.limit_by(limit)
    |> Repo.all()
  end

  def set_skin!(hero, %{id: nil}), do: update!(hero, %{skin_id: nil}) |> Map.put(:skin, nil)
  def set_skin!(hero, skin), do: update!(hero, %{skin_id: skin.id}) |> Map.put(:skin, skin)

  def shard_buyback!(hero), do: update!(hero, %{pve_state: "alive"})

  def start_farming!(hero, state, turns) do
    {:ok, result} =
      Repo.transaction(fn ->
        stored = Repo.one!(from h in Hero, where: h.id == ^hero.id, lock: "FOR UPDATE")

        if state in ["meditating", "mining"] && stored.pve_state == "alive" && is_nil(stored.finished_at) &&
             is_nil(stored.archived_at) && is_nil(Moba.Engine.pending_battle(stored.id)) &&
             is_integer(turns) && turns > 0 && turns <= stored.pve_current_turns do
          update!(stored, %{pve_state: state, pve_farming_turns: turns, pve_farming_started_at: Timex.now()})
        else
          stored
        end
      end)

    get_hero!(result.id)
  end

  def trained_pvp_heroes(player_id, excluded_hero_ids \\ [], limit \\ 5, sort \\ :pvp) do
    HeroQuery.trained(player_id, excluded_hero_ids, limit, sort) |> Repo.all()
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
    |> HeroQuery.solo()
    |> HeroQuery.finished_pve()
    |> HeroQuery.in_current_ranking_date()
    |> Repo.all()
    |> Enum.with_index(1)
    |> Enum.map(fn {hero, index} ->
      update!(hero, %{pve_ranking: index})
    end)
  end

  def unranked_finished_heroes do
    HeroQuery.finished_recently() |> HeroQuery.unranked() |> Repo.all()
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
        # 24_000
        "pvp_master" -> 12..12
        # 30_000
        "pvp_grandmaster" -> 15..15
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
