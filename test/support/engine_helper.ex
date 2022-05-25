defmodule Test.EngineHelper do
  alias Moba.{Engine, Game, Repo}

  def build_basic_battle(attacker, defender) do
    %Engine.Schema.Battle{attacker: attacker, defender: defender}
  end

  def create_basic_battle(attacker, defender) do
    build_basic_battle(attacker, defender)
    |> Engine.begin_battle!()
    |> Repo.preload(:winner)
  end

  def equip_random_items(hero, items) do
    items
    |> Enum.shuffle()
    |> Enum.take(6)
    |> Enum.reduce(hero, fn item, acc ->
      Game.buy_item!(%{acc | gold: 99999}, item)
    end)
  end

  def previous_turn_for(target, turns) do
    Enum.find(turns, fn turn -> turn.number == target.number - 1 end)
  end
end
