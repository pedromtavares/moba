defmodule Moba.Game.TeamTraining do
  @moduledoc "Independent three-hero training with persistent per-hero targets and real combat."
  alias Moba.{Accounts, Game, Repo}
  alias Moba.Game.{Leagues, Targets}
  alias Moba.Game.Query.SkillQuery
  alias Moba.Game.Training.Loadouts
  alias Moba.Game.Training.Combat
  alias Moba.Game.Schema.Player
  alias Moba.Engine.Core.Turns
  @reward_multiplier 3
  @max_gold_farm 30_000

  def draft(scope, player, catalog) do
    %{
      phase: :draft,
      name: if(scope.user, do: scope.user.username),
      player_id: player.id,
      picks: [],
      heroes: %{},
      order: [1, 2, 3],
      selected: 1,
      reward_mode: :shared,
      pve_tier: player.pve_tier,
      goal: Moba.max_available_league(player.pve_tier),
      league_tier: 0,
      league_attempts: 0,
      league_successes: 0,
      turns_left: Moba.turns_per_tier(),
      reserve_turns: Moba.total_pve_turns(player.pve_tier),
      turn: 1,
      targets: %{},
      target_sequence: 0,
      encounters: [],
      catalog: catalog,
      unlocked_codes: if(scope.user, do: Accounts.unlocked_codes_for(scope.user), else: []),
      boss: nil,
      boss_attempts: 0,
      last_result: nil,
      started_at: NaiveDateTime.utc_now()
    }
  end

  def add_pick(_scope, %{phase: :draft} = run, %{"avatar" => avatar_id, "skills" => ids} = params) do
    player = Game.get_player!(run.player_id)

    with true <- length(run.picks) < 3,
         {:ok, avatar, skills} <- Game.Training.creation_loadout(player, avatar_id, ids),
         false <- Enum.any?(run.picks, &(&1.avatar.id == avatar.id)) do
      pick = %{avatar: avatar, skills: skills}
      pick = Map.put(pick, :preset_name, selected_preset(pick, params))
      {:ok, %{run | picks: run.picks ++ [pick]}}
    else
      _ -> {:error, "Choose a different unlocked avatar and three unlocked skills."}
    end
  end

  def add_pick(_, _, _), do: {:error, "This draft is already complete."}

  defp selected_preset(pick, %{"preset" => index}) when is_integer(index) or is_binary(index) do
    with {index, ""} when index >= 0 <- Integer.parse(to_string(index)),
         {skills, name} <- Game.skill_build_for(pick.avatar.role, index),
         true <- same_skills?(skills, pick.skills) do
      name
    else
      _ -> nil
    end
  end

  defp selected_preset(_, %{"preset" => _}), do: nil

  defp selected_preset(pick, _) do
    Enum.find_value(Game.skill_builds_for(pick.avatar.role), fn {skills, name} ->
      if same_skills?(skills, pick.skills), do: name
    end)
  end

  defp same_skills?(left, right), do: MapSet.new(left, & &1.id) == MapSet.new(right, & &1.id)

  def decode_roster(json) when is_binary(json) and byte_size(json) <= 4096 do
    case Jason.decode(json) do
      {:ok, [_, _, _] = picks} -> {:ok, picks}
      _ -> {:error, :invalid_roster}
    end
  end

  def decode_roster(_), do: {:error, :invalid_roster}

  def prepare_run(scope, %{phase: :draft} = run, [_, _, _] = picks, name) do
    with {:ok, run} <- name_team(scope, %{run | picks: []}, name),
         {:ok, run} <-
           Enum.reduce_while(picks, {:ok, run}, fn pick, {:ok, run} ->
             case add_pick(scope, run, pick) do
               {:ok, run} -> {:cont, {:ok, run}}
               {:error, _} = error -> {:halt, error}
             end
           end) do
      {:ok, begin_run(run)}
    end
  end

  def prepare_run(_, _, _, _), do: {:error, "Choose three different unlocked avatars and valid builds."}

  def name_team(%{user: nil}, %{phase: :draft} = run, _), do: {:ok, Map.put(run, :name, nil)}

  def name_team(%{user: %{}}, %{phase: :draft} = run, value) do
    name = if is_binary(value), do: String.trim(value), else: ""

    if String.length(name) in 3..30,
      do: {:ok, Map.put(run, :name, name)},
      else: {:error, {:team_name, "Use 3–30 characters for your team name."}}
  end

  def name_team(_, run, _), do: {:ok, run}

  def begin_run(%{phase: :draft, picks: [_, _, _]} = run) do
    run = %{run | started_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)}

    heroes =
      Map.new(Enum.with_index(run.picks, 1), fn {pick, id} ->
        gold = Moba.initial_gold(%{pve_tier: run.pve_tier})
        h = Loadouts.build_loadout(run.catalog, pick.avatar, :radiant, id, gold)
        skills = Enum.uniq_by(pick.skills ++ List.wrap(pick.avatar.ultimate), & &1.code)

        hero = %{
          h.hero
          | name: Map.get(run, :name) || pick.avatar.name,
            skills: skills,
            skill_order: Game.Skills.default_skill_order(skills),
            pve_tier: run.pve_tier,
            inserted_at: run.started_at
        }

        {id, restore(%{h | hero: hero})}
      end)

    %{run | phase: :playing, heroes: heroes} |> sync_progress() |> refresh_targets([1, 2, 3])
  end

  def begin_run(run), do: run

  def select(%{phase: :playing} = run, id) when id in [1, 2, 3], do: %{run | selected: id}
  def select(run, _), do: run
  def reward_mode(%{phase: :playing} = run, mode) when mode in [:shared, :focus], do: %{run | reward_mode: mode}
  def reward_mode(run, _), do: run
  def team(run), do: Enum.map(run.order, &run.heroes[&1])
  def pending_skill_heroes(run), do: Enum.filter(team(run), &(&1.hero.skill_levels_available > 0))
  def dead?(h), do: h.hero.pve_state == "dead" || h.hp <= 0
  def roster_alive?(run), do: Enum.all?(team(run), &(!dead?(&1)))
  def active_encounter(%{phase: :engagement, encounters: encounters}), do: List.last(encounters)
  def active_encounter(_), do: nil

  def hero_name(%{name: name, avatar: avatar}, %{name: nil, player_id: player_id}) do
    if name == "Guest ##{player_id}", do: avatar.name, else: name
  end

  def hero_name(%{name: name}, _team), do: name

  def boss_preview(%{phase: :playing, turns_left: 0} = run) do
    if run.league_tier == Moba.master_league_tier() && run.league_tier < run.goal do
      boss = run.boss || boss(run)

      put_in(
        boss.hero.skills,
        Enum.uniq_by(boss.hero.skills ++ List.wrap(boss.hero.avatar.ultimate), & &1.code)
      )
    end
  end

  def boss_preview(_), do: nil
  def farm_reward(difficulty, tier), do: @reward_multiplier * Moba.pve_battle_rewards(difficulty, tier)

  def buyback(%{phase: :playing} = run) do
    h = run.heroes[run.selected]
    price = Game.buyback_price(h.hero)

    if dead?(h) && h.hero.gold >= price do
      hero = %{
        h.hero
        | pve_state: "alive",
          buybacks: h.hero.buybacks + 1,
          gold: h.hero.gold - price,
          total_gold_farm: h.hero.total_gold_farm - price
      }

      put_in(run.heroes[h.id], restore(%{h | hero: hero}))
    else
      run
    end
  end

  def buyback(run), do: run

  def can_shard_buyback?(%{phase: :playing} = run) do
    h = run.heroes[run.selected]
    dead?(h) && Game.can_shard_buyback?(h.hero)
  end

  def can_shard_buyback?(_), do: false

  def shard_buyback(run) do
    if can_shard_buyback?(run), do: update_in(run.heroes[run.selected], &revive/1), else: run
  end

  def restart(scope, run) do
    player = Game.get_player!(run.player_id)

    draft(scope, player, run.catalog)
    |> Map.merge(%{picks: run.picks, reward_mode: run.reward_mode, name: Map.get(run, :name)})
    |> begin_run()
  end

  def configure(_scope, %{phase: :playing} = run, operation, value),
    do: Loadouts.configure(run, run.selected, operation, value)

  def configure(_, run, _, _), do: run

  def battle(%{phase: :playing, turns_left: left} = run, target_id) when left > 0 do
    target =
      unless dead?(run.heroes[run.selected]), do: Enum.find(run.targets[run.selected] || [], &(&1.id == target_id))

    case target do
      nil ->
        run

      target ->
        run = %{run | turns_left: left - 1}

        encounter(
          run,
          :farm,
          [run.selected],
          [target.opponent],
          "#{String.capitalize(target.difficulty)} target",
          target.reward
        )
    end
  end

  def battle(run, _), do: run

  def league(%{phase: :playing, turns_left: 0, league_tier: tier} = run) do
    cond do
      !roster_alive?(run) || pending_skill_heroes(run) != [] ->
        run

      tier >= run.goal ->
        run

      tier == Moba.master_league_tier() ->
        boss = boss_preview(run)

        encounter(
          %{run | boss: boss, boss_attempts: run.boss_attempts + 1},
          :boss,
          run.order,
          [boss],
          "Roshan · Final challenge",
          @reward_multiplier * Moba.boss_win_bonus()
        )

      true ->
        next = String.replace(Moba.leagues()[tier + 1], " League", "")

        encounter(
          %{run | league_attempts: run.league_attempts + 1},
          :league,
          run.order,
          league_opponents(run),
          "#{next} · League challenge",
          @reward_multiplier * Moba.league_win_bonus()
        )
    end
  end

  def league(run), do: run

  def battle_action(_scope, %{phase: :engagement} = run, orders) do
    e = active_encounter(run)
    duel = Combat.step(run.resolution.duel, orders)
    e = %{e | duel: duel, battles: List.replace_at(e.battles, -1, duel.battle)}

    if duel.battle.finished do
      result = Combat.result(duel)

      units =
        Enum.reduce(result.results, e.units, fn {id, resources}, units ->
          Map.update!(units, id, &Map.merge(&1, resources))
        end)

      r = hd(e.remaining.radiant)
      d = hd(e.remaining.dire)
      units = if units[r].hp == 0, do: update_in(units[r].deaths, &(&1 + 1)), else: units
      units = if units[d].hp == 0, do: update_in(units[r].kills, &(&1 + 1)), else: units

      remaining = %{
        radiant: Enum.filter(e.remaining.radiant, &(units[&1].hp > 0)),
        dire: Enum.filter(e.remaining.dire, &(units[&1].hp > 0))
      }

      e = %{e | units: units, remaining: remaining}

      if remaining.radiant != [] && remaining.dire != [] && (units[r].hp == 0 || units[d].hp == 0) do
        next =
          if e.kind == :boss do
            Combat.new_duel(units[hd(remaining.radiant)], units[hd(remaining.dire)],
              type: duel.battle.type,
              initiative: :training
            )
          else
            {a, b} =
              if units[r].hp == 0,
                do: {hd(remaining.dire), hd(remaining.radiant)},
                else: {hd(remaining.radiant), hd(remaining.dire)}

            Combat.new_duel(units[a], units[b], type: duel.battle.type)
          end

        put_encounter(run, %{e | duel: next, battles: e.battles ++ [next.battle]})
      else
        winner =
          cond do
            remaining.dire == [] && remaining.radiant != [] -> :radiant
            remaining.radiant == [] && remaining.dire != [] -> :dire
            true -> :draw
          end

        finish(run, %{e | status: :finished, winner: winner})
      end
    else
      put_encounter(run, e)
    end
  end

  def battle_action(_, run, _), do: run

  defp encounter(run, kind, ids, opponents, label, reward) do
    run = sync_progress(run)
    type = if kind == :farm, do: "pve", else: "league"
    radiant = Enum.map(ids, &restore(run.heroes[&1], type))
    opponents = if kind == :boss, do: opponents, else: Enum.map(opponents, &restore/1)
    options = if kind in [:farm, :boss], do: [type: type, initiative: :training], else: [type: type]
    duel = Combat.new_duel(hd(radiant), hd(opponents), options)
    units = Map.new(radiant ++ opponents, &{&1.id, &1})

    e = %{
      turn: run.turn,
      label: label,
      kind: kind,
      league_tier: run.league_tier,
      initiator: if(duel.battle.initiator_id == hd(radiant).id, do: :radiant, else: :dire),
      radiant: radiant,
      dire: opponents,
      units: units,
      remaining: %{radiant: ids, dire: Enum.map(opponents, & &1.id)},
      duel: duel,
      battles: [duel.battle],
      status: :pending,
      winner: nil,
      reward: reward,
      reward_mode: if(kind == :farm, do: run.reward_mode, else: :shared),
      recipient: run.selected
    }

    put_encounter(%{run | phase: :engagement, encounters: [e]}, e)
  end

  defp put_encounter(run, e), do: run |> Map.put(:encounters, [e]) |> Map.put(:resolution, %{duel: e.duel})

  defp finish(run, e) do
    won = e.winner == :radiant

    heroes =
      Enum.reduce(e.radiant, run.heroes, fn h, heroes ->
        unit = e.units[h.id]

        unit =
          if e.kind == :farm do
            hero = %{unit.hero | pve_current_turns: run.turns_left}
            defender = hd(e.dire).hero

            winner =
              case e.winner do
                :radiant -> hero
                :dire -> defender
                :draw -> nil
              end

            updates = Game.Training.pve_score_updates(hero, defender, winner)
            unit = %{unit | hero: struct(hero, updates)}

            if e.winner == :dire && unit.hero.pve_state == "alive", do: restore(unit), else: unit
          else
            unit
          end

        Map.put(heroes, h.id, if(unit.hp <= 0, do: fallen(unit), else: unit))
      end)

    turns_left = if e.kind == :farm, do: heroes[hd(e.radiant).id].hero.pve_current_turns, else: run.turns_left
    run = %{run | turns_left: turns_left}

    mode = if e.kind == :farm, do: e.reward_mode, else: :shared
    e = %{e | reward_mode: mode}
    recipients = if mode == :shared, do: run.order, else: [e.recipient]

    rewards = if won, do: capped_rewards(heroes, recipients, run.order, e.reward), else: []

    totals = %{
      gold: Enum.sum(Enum.map(rewards, fn {_, r} -> r.gold end)),
      xp: Enum.sum(Enum.map(rewards, fn {_, r} -> r.xp end))
    }

    e = Map.put(e, :reward_totals, totals)

    heroes =
      Enum.reduce(rewards, heroes, fn {id, reward}, heroes ->
        Map.update!(heroes, id, &Loadouts.grant_farm(&1, reward.gold, reward.xp, run.catalog))
      end)

    heroes =
      Map.new(heroes, fn {id, h} ->
        recovered =
          cond do
            won && e.kind == :league -> revive(h)
            dead?(h) -> fallen(h)
            true -> restore(h)
          end

        {id, recovered}
      end)

    last = %{
      kind: e.kind,
      winner: e.winner,
      label: e.label,
      rewards: rewards,
      mode: mode,
      league_tier: run.league_tier
    }

    run =
      %{run | phase: :playing, heroes: heroes, encounters: [e], turn: run.turn + 1, last_result: last}
      |> Map.delete(:resolution)

    run =
      case e.kind do
        :farm ->
          run

        :league ->
          tier = run.league_tier + if(won, do: 1, else: 0)
          run = %{run | league_tier: tier, league_successes: run.league_successes + if(won, do: 1, else: 0)}

          cond do
            tier >= run.goal ->
              %{run | phase: :finished}

            run.reserve_turns > 0 ->
              %{
                run
                | turns_left: min(Moba.turns_per_tier(), run.reserve_turns),
                  reserve_turns: max(0, run.reserve_turns - Moba.turns_per_tier())
              }

            true ->
              %{run | phase: :finished}
          end

        :boss ->
          cond do
            won ->
              %{run | phase: :finished, league_tier: Moba.max_league_tier()}

            run.boss_attempts >= 2 ->
              %{run | phase: :finished}

            true ->
              boss = e.units[hd(e.dire).id]
              recovery = trunc(Loadouts.max_hp(boss) * Moba.boss_regeneration_multiplier())
              boss = %{boss | hp: min(Loadouts.max_hp(boss), boss.hp + recovery)}
              %{run | boss: boss}
          end
      end

    run |> sync_progress() |> refresh_targets(run.order)
  end

  defp capped_rewards(heroes, recipients, order, amount) do
    gold_capacity = Map.new(heroes, fn {id, h} -> {id, max(0, @max_gold_farm - h.hero.total_gold_farm)} end)
    xp_capacity = Map.new(heroes, fn {id, h} -> {id, Loadouts.xp_capacity(h)} end)
    gold = distribute_reward(amount, recipients, gold_capacity, order, %{})
    xp = distribute_reward(amount, recipients, xp_capacity, order, %{})

    for id <- order, Map.get(gold, id, 0) > 0 || Map.get(xp, id, 0) > 0 do
      {id, %{gold: Map.get(gold, id, 0), xp: Map.get(xp, id, 0)}}
    end
  end

  defp distribute_reward(0, _, _, _, credits), do: credits

  defp distribute_reward(amount, recipients, capacity, order, credits) do
    eligible = Enum.filter(recipients, &(capacity[&1] > 0))

    case eligible do
      [] ->
        if recipients == order,
          do: credits,
          else: distribute_reward(amount, order, capacity, order, credits)

      ids ->
        {remaining, capacity, credits} =
          Enum.reduce(Enum.with_index(ids), {amount, capacity, credits}, fn {id, index}, {left, capacity, credits} ->
            share = div(amount, length(ids)) + if(index < rem(amount, length(ids)), do: 1, else: 0)
            granted = min(share, capacity[id])

            {left - granted, Map.update!(capacity, id, &(&1 - granted)),
             Map.update(credits, id, granted, &(&1 + granted))}
          end)

        distribute_reward(remaining, order, capacity, order, credits)
    end
  end

  defp restore(h, type \\ "pve"),
    do: %{
      h
      | hp: Turns.buffed_total(h.hero, %{type: type}, Loadouts.max_hp(h)),
        energy: Turns.buffed_total(h.hero, %{type: type}, Loadouts.max_energy(h))
    }

  defp revive(h), do: restore(%{h | hero: %{h.hero | pve_state: "alive"}})
  defp fallen(h), do: %{h | hp: 0, energy: 0, hero: %{h.hero | pve_state: "dead"}}

  defp sync_progress(run) do
    heroes =
      Map.new(run.heroes, fn {id, h} ->
        hero = %{
          h.hero
          | league_tier: run.league_tier,
            pve_current_turns: run.turns_left,
            pve_total_turns: run.reserve_turns,
            league_attempts: run.league_attempts,
            league_successes: run.league_successes,
            pve_state: if(dead?(h), do: "dead", else: "alive"),
            inserted_at: run.started_at
        }

        {id, %{h | hero: hero}}
      end)

    %{run | heroes: heroes}
  end

  def refresh_targets(run, ids) do
    Enum.reduce(ids, run, fn id, current ->
      difficulties =
        if run.pve_tier == 0 do
          ["weak", "weak", "moderate"]
        else
          Targets.difficulty_counts(run.pve_tier)
          |> Tuple.to_list()
          |> Enum.zip(["weak", "moderate", "strong"])
          |> Enum.flat_map(fn {count, difficulty} -> List.duplicate(difficulty, div(count, 3)) end)
        end

      current = put_in(current.targets[id], [])

      Enum.reduce(difficulties, current, fn difficulty, acc ->
        sequence = acc.target_sequence + 1
        excluded = Enum.map(acc.targets[id], & &1.bot_id) |> Enum.reject(&is_nil/1)
        candidate = Targets.candidates(acc.heroes[id].hero, difficulty, acc.unlocked_codes, 1, excluded) |> List.first()

        opponent =
          if candidate,
            do: wrap_opponent(candidate, 1000 + sequence),
            else: fallback_opponent(acc, acc.heroes[id], difficulty, 1000 + sequence)

        target = %{
          id: sequence,
          difficulty: difficulty,
          defender: opponent.hero,
          opponent: opponent,
          reward: farm_reward(difficulty, run.pve_tier),
          bot_id: candidate && candidate.id
        }

        %{acc | target_sequence: sequence} |> update_in([:targets, id], &(&1 ++ [target]))
      end)
    end)
  end

  defp wrap_opponent(hero, id) do
    hero = %{hero | id: id, player: %Player{id: -2, current_immortal_streak: 0}, player_id: nil}

    %{
      id: id,
      side: :dire,
      hero: hero,
      hp: hero.total_hp + hero.item_hp,
      energy: hero.total_mp + hero.item_mp,
      kills: 0,
      deaths: 0,
      inventory: [],
      auto_buy: false,
      final_build: []
    }
  end

  defp fallback_opponent(run, fighter, difficulty, id) do
    avatar = Enum.random(Game.list_creation_avatars(run.unlocked_codes)) |> Repo.preload(:ultimate)
    h = Loadouts.build_loadout(run.catalog, avatar, :dire, id)

    offset =
      case difficulty do
        "weak" -> -1200
        "moderate" -> -600
        _ -> 1200
      end

    h =
      h
      |> Loadouts.grant_farm(
        max(0, fighter.hero.total_gold_farm + offset),
        max(0, fighter.hero.total_xp_farm + offset),
        run.catalog
      )
      |> Loadouts.automate_skills(run.catalog)

    scale = if difficulty == "weak", do: 0.65, else: 1.0

    %{
      h
      | hero: %{
          h.hero
          | bot_difficulty: difficulty,
            total_hp: round(h.hero.total_hp * scale),
            atk: max(1, round(h.hero.atk * scale))
        }
    }
    |> restore()
  end

  defp league_opponents(run) do
    tier = run.league_tier
    last = Leagues.max_league_step_for(tier)

    # Solo starts at step 1. The Silver challenge uses step 0 to fill its third slot.
    for {step, id} <- Enum.with_index((last - 2)..last, 2000) do
      case Leagues.league_defender_for(%{id: -1, league_tier: tier, league_step: step}) do
        nil ->
          {level, difficulty} = Leagues.defender_profile(tier, step)
          avatar = Enum.random(run.catalog.avatars)
          xp = Enum.sum(Enum.map(2..level, &Game.xp_to_next_hero_level/1))
          league_tier = Leagues.league_tier_for(level)
          gold = 4800 * league_tier + if(difficulty == "strong", do: 2400, else: 1200)
          unit = Loadouts.build_loadout(run.catalog, avatar, :dire, id)
          unit = %{unit | hero: %{unit.hero | bot_difficulty: difficulty, league_tier: league_tier}}
          unit |> Loadouts.grant_farm(gold, xp, run.catalog) |> Loadouts.automate_skills(run.catalog) |> restore()

        candidate ->
          candidate
          |> Repo.preload([:avatar, :items, :skin, skills: SkillQuery.ordered()])
          |> wrap_opponent(id)
      end
    end
  end

  defp boss(run) do
    avatar = Game.Avatars.boss!() |> Repo.preload(:ultimate)
    skills = Game.Skills.boss!()
    catalog = %{run.catalog | builds: Map.put(run.catalog.builds, avatar.id, %{skills: skills, items: []})}
    h = Loadouts.build_loadout(catalog, avatar, :dire, 3000)

    %{
      h
      | hero: %{
          h.hero
          | name: "Roshan",
            bot_difficulty: "boss",
            level: 25,
            total_hp: 10_000,
            items: [],
            gold: 0,
            item_hp: 0,
            item_mp: 0,
            item_atk: 0,
            item_power: 0,
            item_armor: 0,
            item_speed: 0,
            skill_order: Enum.filter(skills, &(!&1.passive)) |> Enum.map(& &1.code)
        },
        auto_buy: false,
        inventory: []
    }
    |> restore()
  end
end
