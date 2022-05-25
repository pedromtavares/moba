defmodule Moba.Engine do
  @moduledoc """
  Top-level domain of all logic related to the battle engine
  """

  alias Moba.{Game, Engine}
  alias Engine.{Battles, Core}

  def battle_types, do: %{pve: "pve", league: "league", duel: "duel"}

  # BATTLE MANAGEMENT

  defdelegate first_duel_battle(duel), to: Battles

  defdelegate generate_attacker_snapshot!(tuple), to: Battles

  defdelegate generate_defender_snapshot!(tuple), to: Battles

  defdelegate get_battle!(id), to: Battles

  defdelegate last_duel_battle(duel), to: Battles

  defdelegate latest_battle(hero_id), to: Battles

  defdelegate list_battles(hero, type), to: Battles

  defdelegate list_duel_battles(duel_ids), to: Battles

  defdelegate ordered_turns_query, to: Battles

  defdelegate pending_battle(hero_id), to: Battles

  defdelegate update_battle!(battle, attrs), to: Battles

  # CORE MECHANICS

  defdelegate auto_finish_battle!(battle, orders \\ %{auto: true}), to: Core

  defdelegate begin_battle!(battle), to: Core

  defdelegate build_turn(battle, orders \\ %{}), to: Core

  defdelegate can_use_resource?(turn, resource), to: Core

  defdelegate continue_battle!(battle, orders), to: Core

  defdelegate create_pve_battle!(target), to: Core

  def create_league_battle!(attacker) do
    Core.create_league_battle!(attacker, Game.league_defender_for(attacker))
  end

  defdelegate create_duel_battle!(attrs), to: Core

  defdelegate effect_descriptions(turn), to: Core

  defdelegate last_turn(battle), to: Core
end
