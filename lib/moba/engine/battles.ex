defmodule Moba.Engine.Battles do
  @moduledoc """
  Manages Battle records and queries
  """

  alias Moba.{Repo, Engine}
  alias Engine.Schema.{Turn, Battle}

  import Ecto.Query, only: [from: 2]

  def get!(id, skills_query) do
    Repo.get!(Battle, id)
    |> Repo.preload([
      :initiator,
      :winner,
      turns: ordered_turns_query(),
      attacker: [:items, :avatar, :skin, :user, active_build: [skills: skills_query]],
      defender: [:items, :avatar, :skin, :user, active_build: [skills: skills_query]]
    ])
  end

  def update!(battle, attrs) do
    battle
    |> Battle.changeset(attrs)
    |> Repo.update!()
  end

  def list(hero, type, page, limit) do
    offset = (page - 1) * limit

    base =
      from b in Battle,
        limit: ^limit,
        where: b.finished == true,
        offset: ^offset,
        order_by: [desc: b.id]

    query =
      case type do
        "pvp_defended" ->
          from b in base,
            where: b.defender_id == ^hero.id,
            where: b.type == "pvp"

        _ ->
          from b in base,
            where: b.attacker_id == ^hero.id,
            where: b.type == ^type
      end

    query
    |> Repo.all()
    |> Repo.preload([:winner, defender: [:avatar], attacker: [:avatar]])
  end

  def ordered_turns_query, do: from(t in Turn, order_by: t.number)

  def pending_for(hero_id) do
    from(b in Battle, where: b.attacker_id == ^hero_id, where: b.finished == false, limit: 1)
    |> Repo.all()
    |> List.first()
  end

  def latest_for(hero_id) do
    from(b in Battle, where: b.attacker_id == ^hero_id, order_by: [desc: :id], limit: 1)
    |> Repo.all()
    |> List.first()
  end

  def read!(battle), do: update!(battle, %{unread_id: nil})

  def unreads_for(hero) do
    unreads_query(hero)
    |> Repo.aggregate(:count)
  end

  def read_all, do: update_unread(Battle)

  def read_all_for_hero(hero) do
    hero
    |> unreads_query()
    |> update_unread()
  end

  @doc """
  Snapshots keep a permanent state of both heroes when the battle finishes
  """
  def generate_attacker_snapshot!({battle, attacker}), do: generate_attacker_snapshot!({battle, attacker, nil})

  def generate_attacker_snapshot!({battle, attacker, _}) do
    update!(battle, %{attacker_snapshot: snapshot_for(attacker, battle.attacker)})
  end

  def generate_defender_snapshot!({battle, _, defender}) do
    update!(battle, %{defender_snapshot: snapshot_for(defender, battle.defender)})
  end

  defp unreads_query(hero) do
    from b in Battle,
      where: b.unread_id == ^hero.id,
      where: b.type == "pvp"
  end

  defp update_unread(query) do
    Repo.update_all(query, set: [unread_id: nil])
  end

  defp snapshot_for(hero, battle_hero) do
    %{
      level: hero.level,
      experience: hero.experience,
      leveled_up: hero.level != battle_hero.level,
      gold: hero.gold,
      skill_levels_available: hero.skill_levels_available,
      wins: hero.wins,
      losses: hero.losses,
      ties: hero.ties,
      pve_points: hero.pve_points,
      pvp_points: hero.pvp_points,
      league_step: hero.league_step,
      previous_league_step: battle_hero.league_step,
      league_tier: hero.league_tier,
      pvp_wins: hero.pvp_wins,
      pvp_losses: hero.pvp_losses,
      pvp_ranking: hero.pvp_ranking,
      buffed_battles_available: hero.buffed_battles_available
    }
  end
end
