defmodule Moba.Engine.Battles do
  @moduledoc """
  Manages Battle records and queries
  """

  alias Moba.{Repo, Engine, Game}
  alias Engine.Schema.{Turn, Battle}
  alias Game.Query.HeroQuery

  import Ecto.Query

  def get_battle!(id), do: Repo.get!(load(), id) |> load_resources()

  def update_battle!(battle, attrs) do
    battle
    |> Battle.changeset(attrs)
    |> Repo.update!()
  end

  def list_battles(hero, type) do
    base =
      from b in Battle,
        where: b.finished == true,
        order_by: [desc: b.id]

    query =
      from b in base,
        where: b.attacker_id == ^hero.id,
        where: b.type == ^type

    query
    |> load()
    |> Repo.all()
  end

  def ordered_turns_query, do: from(t in Turn, order_by: t.number)

  def pending_battle(hero_id) do
    from(b in Battle, where: b.attacker_id == ^hero_id, where: b.finished == false, limit: 1, where: b.type != "duel")
    |> Repo.all()
    |> List.first()
  end

  def latest_battle(hero_id) do
    from(b in Battle, where: b.attacker_id == ^hero_id, order_by: [desc: :id], limit: 1)
    |> Repo.all()
    |> List.first()
  end

  def list_duel_battles(duel_ids) do
    from(b in Battle, where: b.duel_id in ^duel_ids)
    |> Repo.all()
    |> Repo.preload([:winner, attacker: :avatar, defender: :avatar])
  end

  def first_duel_battle(%{player_first_pick_id: pick_id}) when is_nil(pick_id), do: nil

  def first_duel_battle(%{player_first_pick_id: pick_id, id: id}) do
    from(b in for_duel(id), where: b.attacker_id == ^pick_id, order_by: [desc: :id], limit: 1)
    |> load()
    |> Repo.all()
    |> List.first()
  end

  def last_duel_battle(%{opponent_second_pick_id: pick_id}) when is_nil(pick_id), do: nil

  def last_duel_battle(%{opponent_second_pick_id: pick_id, id: id}) do
    from(b in for_duel(id), where: b.attacker_id == ^pick_id, order_by: [desc: :id], limit: 1)
    |> load()
    |> Repo.all()
    |> List.first()
  end

  @doc """
  Snapshots keep a permanent state of both heroes when the battle finishes
  """
  def generate_attacker_snapshot!({battle, attacker}), do: generate_attacker_snapshot!({battle, attacker, nil})

  def generate_attacker_snapshot!({battle, attacker, _}) do
    update_battle!(battle, %{attacker_snapshot: snapshot_for(attacker, battle.attacker)})
  end

  def generate_defender_snapshot!({battle, _, defender}) do
    update_battle!(battle, %{defender_snapshot: snapshot_for(defender, battle.defender)})
  end

  defp for_duel(query \\ Battle, duel_id), do: from(b in query, where: b.duel_id == ^duel_id)

  defp load(queryable \\ Battle) do
    queryable
    |> preload([
      :initiator,
      :winner,
      duel: [player: :user, opponent_player: :user],
      turns: ^ordered_turns_query(),
      attacker: ^HeroQuery.load(),
      defender: ^HeroQuery.load()
    ])
  end

  defp load_resources(%{turns: turns} = battle) do
    turns = Enum.map(turns, fn turn ->
      %{turn | 
        skill: Moba.load_resource(turn.skill_code),
        item: Moba.load_resource(turn.item_code)
      }
    end)
    Map.put(battle, :turns, turns)
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
      league_step: hero.league_step,
      previous_league_step: battle_hero.league_step,
      league_tier: hero.league_tier
    }
  end
end
