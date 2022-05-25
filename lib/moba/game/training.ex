defmodule Moba.Game.Training do
  @moduledoc """
  Module focused on cross-domain orchestration and logic related to hero training (single-player)
  """
  alias Moba.{Accounts, Game, Repo}
  alias Game.{Avatars, Heroes, Skills, Targets}

  def archive_hero!(%{user: user} = hero) do
    if user.current_pve_hero_id == hero.id, do: Accounts.set_current_pve_hero!(user, nil)
    update_hero!(hero, %{archived_at: DateTime.utc_now()})
  end

  def broadcast_to_hero(hero_id) do
    MobaWeb.broadcast("hero-#{hero_id}", "hero", %{id: hero_id})
  end

  @doc """
  Orchestrates the creation of a Hero, which involves creating it and generating its first Training targets
  """
  def create_hero!(attrs, user, avatar, skills) do
    attrs =
      if user && user.pve_tier >= 4 do
        Map.put(attrs, :refresh_targets_count, Moba.refresh_targets_count(user.pve_tier))
      else
        attrs
      end

    attrs
    |> Heroes.create!(user, avatar, skills)
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

  def finish_farming!(hero) do
    hero
    |> Heroes.finish_farming!()
    |> generate_targets!()
  end

  def finish_pve!(%{finished_at: nil} = hero) do
    hero =
      hero
      |> update_hero!(%{finished_at: Timex.now()})
      |> Game.track_pve_quests()

    Moba.run_async(fn ->
      update_pve_ranking!()
      update_hero_collection!(hero)
    end)

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
    hero = Repo.preload(hero, :user)
    codes = (hero.user && Accounts.unlocked_codes_for(hero.user)) || []
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

  def refresh_targets!(%{refresh_targets_count: count} = hero) when count > 0 do
    generate_targets!(hero)

    update_hero!(hero, %{refresh_targets_count: count - 1})
  end

  def refresh_targets!(hero), do: hero

  def shard_buyback!(%{user: user} = hero) do
    if Accounts.shard_buyback!(user) do
      update_hero!(hero, %{pve_state: "alive"})
    else
      hero
    end
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
    hero = Repo.preload(hero, :user)
    collection = Heroes.collection_for(hero.user_id)
    if length(collection) > 0, do: Accounts.update_collection!(hero.user, collection)

    hero
  end

  def update_pve_ranking! do
    Heroes.update_pve_ranking!()
    MobaWeb.broadcast("hero-ranking", "ranking", %{})
  end
end
