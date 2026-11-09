defmodule Moba.Game.Training do
  @moduledoc """
  Module focused on cross-resource orchestration and logic related to hero training (single-player)
  """
  alias Moba.{Engine, Game, Repo}
  alias Game.{Avatars, Heroes, Leagues, Players, Quests, Skills, Targets}
  alias Game.Schema.Player
  import Ecto.Query, only: [from: 2]

  @doc "Validates an untrusted creation selection against the player's unlocked, level-one resources."
  def creation_loadout(player, avatar_id, skill_ids)
      when is_list(skill_ids) and length(skill_ids) == 3 and (is_binary(avatar_id) or is_integer(avatar_id)) do
    if Enum.all?(skill_ids, &(is_binary(&1) || is_integer(&1))) do
      codes =
        if player && player.user_id,
          do: Moba.Accounts.get_user_with_unlocks!(player.user_id) |> Moba.Accounts.unlocked_codes_for(),
          else: []

      avatar = Enum.find(Game.list_creation_avatars(codes), &(to_string(&1.id) == to_string(avatar_id)))
      allowed = Game.list_creation_skills(1, codes)
      ids = Enum.map(skill_ids, &to_string/1)
      skills = Enum.filter(allowed, &(to_string(&1.id) in ids))

      if avatar && length(ids) == 3 && length(Enum.uniq(ids)) == 3 && length(skills) == 3,
        do: {:ok, avatar, skills},
        else: {:error, :invalid_loadout}
    else
      {:error, :invalid_loadout}
    end
  end

  def creation_loadout(_, _, _), do: {:error, :invalid_loadout}

  def invoke_hero(player, attrs, avatar_id, skill_ids) do
    player = Players.get_player!(player.id)

    with {:ok, avatar, skills} <- creation_loadout(player, avatar_id, skill_ids) do
      {:ok, create_current_pve_hero!(attrs, player, avatar, skills)}
    end
  end

  @doc "Creates a guest and their first hero once per browser start session."
  def start_guest!(session_key, avatar, skills) when is_binary(session_key) do
    {:ok, player} =
      Repo.transaction(fn ->
        inserted =
          %Player{season_id: Game.current_season().id}
          |> Player.changeset(%{})
          |> Ecto.Changeset.put_change(:guest_session_key, session_key)
          |> Repo.insert!(on_conflict: :nothing, conflict_target: :guest_session_key)

        player = Repo.get_by!(Player, guest_session_key: session_key)

        # A conflicting insert has no generated ID. It waits for the first
        # transaction to finish, then reuses that player without creating a hero.
        if inserted.id do
          create_current_pve_hero!(%{name: avatar.name}, player, avatar, skills)
        end

        Players.get_player!(player.id)
      end)

    player
  end

  def archive_hero!(%{player: player} = hero) do
    Repo.update_all(
      from(p in Player, where: p.id == ^player.id and p.current_pve_hero_id == ^hero.id),
      set: [current_pve_hero_id: nil]
    )

    unless hero.finished_at, do: Players.add_total_farm!(hero)
    hero = update_hero!(hero, %{archived_at: DateTime.utc_now()})
    if hero.finished_at, do: refresh_hero_collection!(hero.player_id)
    hero
  end

  def broadcast_to_hero(hero_id) do
    MobaWeb.broadcast("hero-#{hero_id}", "hero", %{id: hero_id})
  end

  def create_current_pve_hero!(attrs, player, avatar, skills) do
    {:ok, hero} =
      Repo.transaction(fn ->
        stored = Repo.one!(from p in Player, where: p.id == ^player.id, lock: "FOR UPDATE")

        if stored.current_pve_hero_id && stored.current_pve_hero_id != player.current_pve_hero_id do
          # Another request already invoked a hero from this player's snapshot.
          Game.get_hero!(stored.current_pve_hero_id)
        else
          hero = create_hero!(attrs, stored, avatar, skills)
          Players.set_current_pve_hero!(stored, hero.id)
          hero
        end
      end)

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

    score_updates = pve_score_updates(attacker, defender, winner)

    attacker
    |> update_attacker!(Map.merge(reward_updates, score_updates))
    |> maybe_generate_boss()
    |> maybe_finish_pve()
  end

  @doc "Shared target-battle results, including loss-turn refunds and beginner death protection."
  def pve_score_updates(attacker, defender, winner) do
    if winner && winner.id == defender.id do
      state = if attacker.pve_tier < 1, do: "alive", else: "dead"

      %{losses: attacker.losses + 1, pve_state: state, pve_current_turns: attacker.pve_current_turns + 1}
    else
      wins = if winner && winner.id == attacker.id, do: attacker.wins + 1, else: attacker.wins
      %{wins: wins}
    end
  end

  def finish_farming!(hero) do
    {updated, claimed?} = Heroes.claim_farming!(hero)
    if claimed?, do: generate_targets!(updated), else: updated
  end

  def finish_pve!(%{finished_at: nil} = hero) do
    hero = update_hero!(hero, %{finished_at: Timex.now()})

    Quests.track_pve_progression!(hero)
    Players.add_total_farm!(hero)
    refresh_hero_collection!(hero.player_id)
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

  def refresh_targets!(hero) do
    {:ok, updated} =
      Repo.transaction(fn ->
        Repo.one!(from h in Game.Schema.Hero, where: h.id == ^hero.id, lock: "FOR UPDATE")
        hero = Heroes.get_hero!(hero.id)

        if hero.refresh_targets_count > 0 do
          generate_targets!(hero)
          Heroes.update!(hero, %{refresh_targets_count: hero.refresh_targets_count - 1})
        else
          hero
        end
      end)

    broadcast_to_hero(updated.id)
    updated
  end

  def start_pve_battle!(%{attacker: attacker} = target) do
    with_training_hero(attacker, fn hero ->
      if hero.pve_current_turns < 1 || hero.league_step > 0 do
        {:error, "Not enough available turns"}
      else
        updated = update_hero!(hero, %{pve_current_turns: hero.pve_current_turns - 1})
        battle = Engine.create_pve_battle!(%{target | attacker: updated})
        generate_targets!(updated)
        battle
      end
    end)
  end

  def start_league_battle!(hero) do
    with_training_hero(hero, fn hero ->
      attacker =
        if hero.league_step == 0 do
          update_hero!(hero, %{league_step: 1, league_attempts: hero.league_attempts + 1})
        else
          hero
        end

      defender = Leagues.league_defender_for(attacker)
      Engine.create_league_battle!(%{attacker: attacker, defender: defender})
    end)
  end

  defp with_training_hero(hero, play) do
    {:ok, result} =
      Repo.transaction(fn ->
        Repo.one!(from h in Game.Schema.Hero, where: h.id == ^hero.id, lock: "FOR UPDATE")
        hero = Heroes.get_hero!(hero.id)

        cond do
          hero.pve_state != "alive" || hero.finished_at || hero.archived_at ->
            {:error, "Hero is not available for battle"}

          pending = Engine.pending_battle(hero.id) ->
            Engine.get_battle!(pending.id)

          true ->
            play.(hero)
        end
      end)

    result
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
    refresh_hero_collection!(hero.player_id)
    Repo.preload(hero, :player)
  end

  def refresh_hero_collection!(nil), do: :ok

  def refresh_hero_collection!(player_id) do
    {:ok, player} =
      Repo.transaction(fn ->
        if player = Repo.one(from p in Player, where: p.id == ^player_id, lock: "FOR UPDATE") do
          Players.update_collection!(player, Heroes.collection_for(player_id))
        end
      end)

    player
  end

  def backfill_hero_collections! do
    finished_players =
      from(h in Game.Schema.Hero,
        where: not is_nil(h.finished_at) and is_nil(h.archived_at),
        select: h.player_id
      )

    player_ids =
      from(p in Player,
        where: p.id in subquery(finished_players) or fragment("jsonb_array_length(?) > 0", p.hero_collection),
        select: p.id
      )
      |> Repo.all()

    Enum.each(player_ids, &refresh_hero_collection!/1)
    length(player_ids)
  end
end
