defmodule Moba.Game.Training do
  @moduledoc """
  Module focused on cross-resource orchestration and logic related to hero training (single-player)
  """
  alias Moba.{Engine, Game, Repo, Utils}
  alias Game.{Avatars, Heroes, Leagues, Players, Quests, Skills, Targets}

  def archive_hero!(%{player: player} = hero) do
    if player.current_pve_hero_id == hero.id, do: Players.set_current_pve_hero!(player, nil)
    unless hero.finished_at, do: Players.add_total_farm!(hero)
    update_hero!(hero, %{archived_at: DateTime.utc_now()})
  end

  def broadcast_to_hero(hero_id) do
    MobaWeb.broadcast("hero-#{hero_id}", "hero", %{id: hero_id})
  end

  def create_current_pve_hero!(attrs, player, avatar, skills) do
    hero = create_hero!(attrs, player, avatar, skills)
    Players.set_current_pve_hero!(player, hero.id)
    hero
  end

  @doc """
  Orchestrates the creation of a Hero, which involves creating it and generating its first Training targets
  """
  def create_hero!(attrs, player, avatar, skills) do
    attrs =
      if player && player.pve_tier >= 4 do
        Map.put(attrs, :refresh_targets_count, Moba.refresh_targets_count(player.pve_tier))
      else
        attrs
      end

    attrs
    |> Heroes.create!(player, avatar, skills)
    |> generate_targets!()
  end

  def finalize_boss!(%{league_attempts: 0} = boss, boss_current_hp, hero) do
    maximum_hp = boss.avatar.total_hp
    new_total = boss_current_hp + Moba.boss_regeneration_multiplier() * maximum_hp
    new_total = if new_total > maximum_hp, do: maximum_hp, else: trunc(new_total)
    update_hero!(boss, %{total_hp: new_total, league_attempts: 1})
    update_hero!(hero, %{pve_state: "dead"})
  end

  def finalize_boss!(_, _, hero), do: update_hero!(hero, %{boss_id: nil, pve_state: "dead"})

  def finalize_league_attacker!(attacker, winner) do
    %{
      league_step: step,
      league_successes: successes,
      league_tier: league_tier,
      pve_total_turns: pve_total_turns,
      pve_current_turns: pve_current_turns
    } = attacker

    win = winner && attacker.id == winner.id

    {total_turns, current_turns} =
      if pve_total_turns >= Moba.turns_per_tier() do
        current = pve_current_turns + Moba.turns_per_tier()
        total = pve_total_turns - Moba.turns_per_tier()
        {total, current}
      else
        {0, 0}
      end

    league_bonus =
      if attacker.league_tier == Moba.master_league_tier() do
        Moba.boss_win_bonus()
      else
        Moba.league_win_bonus()
      end

    updates =
      cond do
        win && step >= Leagues.max_league_step_for(league_tier) ->
          next_league_tier = league_tier + 1

          %{
            league_step: 0,
            league_tier: next_league_tier,
            league_successes: successes + 1,
            gold: attacker.gold + league_bonus,
            total_xp: league_bonus,
            boss_id: nil,
            pve_current_turns: current_turns,
            pve_total_turns: total_turns,
            total_gold_farm: attacker.total_gold_farm + league_bonus
          }

        win ->
          %{
            league_step: step + 1
          }

        league_tier == Moba.master_league_tier() ->
          %{
            league_step: 1
          }

        true ->
          %{
            league_step: 0,
            pve_current_turns: current_turns,
            pve_total_turns: total_turns,
            pve_state: "dead"
          }
      end

    attacker = update_attacker!(attacker, updates)

    if winner && attacker.id == winner.id && attacker.league_step > 0 do
      start_league_battle!(attacker)
    end

    attacker
    |> maybe_generate_boss()
    |> maybe_finish_pve()
  end

  def finalize_pve_attacker!(attacker, defender, winner, %{total_xp: total_xp, total_gold: total_gold}) do
    reward_updates = %{
      total_xp: total_xp,
      gold: attacker.gold + total_gold,
      total_gold_farm: attacker.total_gold_farm + total_gold
    }

    score_updates =
      if winner && winner.id == defender.id do
        state = if attacker.pve_tier < 1, do: "alive", else: "dead"

        %{losses: attacker.losses + 1, pve_state: state, pve_current_turns: attacker.pve_current_turns + 1}
      else
        wins = if winner && winner.id == attacker.id, do: attacker.wins + 1, else: attacker.wins

        %{wins: wins}
      end

    attacker
    |> update_attacker!(Map.merge(reward_updates, score_updates))
    |> maybe_generate_boss()
    |> maybe_finish_pve()
  end

  def finish_farming!(hero) do
    hero
    |> Heroes.finish_farming!()
    |> generate_targets!()
  end

  def finish_pve!(%{finished_at: nil} = hero) do
    hero = update_hero!(hero, %{finished_at: Timex.now()})

    Quests.track_pve_progression!(hero)
    Players.add_total_farm!(hero)
    Moba.rank_finished_heroes()

    hero
  end

  def finish_pve!(hero), do: hero

  def generate_boss!(hero) do
    boss =
      Heroes.create!(
        %{name: "Roshan", league_tier: 6, level: 25, bot_difficulty: "boss", boss_id: hero.id},
        nil,
        Avatars.boss!(),
        Skills.boss!()
      )

    update_hero!(hero, %{boss_id: boss.id})
  end

  def generate_targets!(hero) do
    hero = Repo.preload(hero, player: [:user])
    codes = (hero.player && hero.player.user && Moba.unlocked_codes_for(hero.player.user)) || []
    Targets.generate!(hero, codes)
  end

  def master_league?(%{league_tier: tier}), do: tier == Moba.master_league_tier()

  def max_league?(%{league_tier: league_tier, pve_tier: pve_tier}) do
    league_tier == Moba.max_available_league(pve_tier)
  end

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

  def maybe_generate_boss(
        %{pve_current_turns: 5, pve_total_turns: 0, boss_id: nil, pve_state: "alive", league_tier: 5} = hero
      ) do
    generate_boss!(hero)
  end

  def maybe_generate_boss(hero), do: hero

  def rank_finished_heroes! do
    heroes = Heroes.unranked_finished_heroes()
    Heroes.update_pve_ranking!()
    Enum.map(heroes, &update_hero_collection!(&1))
  end

  def refresh_targets!(%{refresh_targets_count: count} = hero) when count > 0 do
    generate_targets!(hero)

    update_hero!(hero, %{refresh_targets_count: count - 1})
  end

  def refresh_targets!(hero), do: hero

  def start_pve_battle!(%{attacker: %{pve_current_turns: turns}}) when turns < 1 do
    {:error, "Not enough available turns"}
  end

  def start_pve_battle!(%{attacker: attacker} = target) do
    Utils.run_async(fn -> generate_targets!(attacker) end)
    updated = update_hero!(attacker, %{pve_current_turns: attacker.pve_current_turns - 1})
    Engine.create_pve_battle!(%{target | attacker: updated})
  end

  def start_league_battle!(hero) do
    attacker =
      if hero.league_step == 0 do
        update_hero!(hero, %{league_step: 1, league_attempts: hero.league_attempts + 1})
      else
        hero
      end

    defender = Leagues.league_defender_for(attacker)
    Engine.create_league_battle!(%{attacker: attacker, defender: defender})
  end

  def subscribe_to_hero(hero_id) do
    MobaWeb.subscribe("hero-#{hero_id}")
    hero_id
  end

  def update_attacker!(hero, updates) do
    updated = Heroes.update_attacker!(hero, updates)
    broadcast_to_hero(hero.id)
    updated
  end

  def update_hero!(hero, attrs, items \\ nil, skills \\ nil) do
    updated = Heroes.update!(hero, attrs, items, skills)
    broadcast_to_hero(hero.id)
    updated
  end

  def update_hero_collection!(hero) do
    hero = Repo.preload(hero, :player)
    collection = Heroes.collection_for(hero.player_id)
    if length(collection) > 0, do: Players.update_collection!(hero.player, collection)

    hero
  end
end
