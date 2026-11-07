defmodule Test.EngineHelper do
  alias Moba.{Engine, Repo}

  def build_basic_battle(attacker, defender) do
    %Engine.Schema.Battle{
      attacker: attacker,
      defender: defender,
      defender_player: defender.player,
      attacker_player: attacker.player
    }
  end

  def create_basic_battle(attacker, defender) do
    build_basic_battle(attacker, defender)
    |> Engine.begin_battle!()
    |> Repo.preload(:winner)
    |> Repo.preload(:winner_player)
  end

  def previous_turn_for(target, turns) do
    Enum.find(turns, fn turn -> turn.number == target.number - 1 end)
  end
end
