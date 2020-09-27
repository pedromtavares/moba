defmodule Moba.Engine do
  @moduledoc """
  Top-level domain of all battle related logic

  As a top-level domain, it can access its siblings like Game and Accounts, its parent (Moba)
  and all of its children (Core, Battles). It cannot, however, access children of its
  siblings.
  """

  alias Moba.{Game, Engine}
  alias Engine.{Battles, Core}

  def battle_types, do: %{pve: "pve", pvp: "pvp", league: "league"}

  # BATTLES MANAGEMENT

  def get_battle!(id), do: Battles.get!(id, Game.ordered_skills_query())

  def update_battle!(battle, attrs), do: Battles.update!(battle, attrs)

  def list_battles(hero, type, page \\ 1, limit \\ 5, match \\ Moba.current_match()) do
    Battles.list(hero, type, page, limit, match)
  end

  def pending_battle(hero_id), do: Battles.pending_for(hero_id)

  def latest_battle(hero_id), do: Battles.latest_for(hero_id)

  def read_battle!(battle), do: Battles.read!(battle)

  def unread_battles_count(hero), do: Battles.unreads_for(hero)

  def read_all_battles, do: Battles.read_all()

  def read_all_battles_for(hero) do
    Battles.read_all_for_hero(hero)
    broadcast_unread(hero)
  end

  def broadcast_unread(hero), do: MobaWeb.broadcast("hero-#{hero.id}", "unread", %{hero_id: hero.id})

  def generate_attacker_snapshot!(tuple), do: Battles.generate_attacker_snapshot!(tuple)

  def generate_defender_snapshot!(tuple), do: Battles.generate_defender_snapshot!(tuple)

  def ordered_turns_query, do: Battles.ordered_turns_query()

  # CORE MECHANICS

  def create_pve_battle!(target), do: Core.create_pve_battle!(target)

  def create_pvp_battle!(attrs), do: Core.create_pvp_battle!(attrs)

  def create_league_battle!(attacker) do
    Core.create_league_battle!(attacker, Game.league_defender_for(attacker))
  end

  def start_battle!(battle), do: Core.start_battle!(battle)

  def continue_battle!(battle, orders), do: Core.continue_battle!(battle, orders)

  def auto_finish_battle!(battle, orders \\ %{auto: true}), do: Core.auto_finish_battle!(battle, orders)

  def next_battle_turn(battle), do: Core.build_turn(battle, %{})

  def last_turn(battle), do: Core.last_turn(battle)

  def can_pvp?(attacker, defender), do: Core.can_pvp?(%{attacker: attacker, defender: defender})

  def effect_descriptions(turn), do: Core.effect_descriptions(turn)

  def can_use_resource?(turn, resource), do: Core.can_use_resource?(turn, resource)
end
