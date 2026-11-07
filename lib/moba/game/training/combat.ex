defmodule Moba.Game.Training.Combat do
  @moduledoc "Runs team training through the shared combat processor."
  alias Moba.Engine.Core
  alias Moba.Engine.Core.{Turns, Processor}
  alias Moba.Engine.Schema.Battle

  defp rng do
    if :rand.export_seed() == :undefined, do: :rand.seed(:exsss)
    :rand.export_seed()
  end

  def new_duel(attacker, defender, opts \\ []) do
    a = attacker.hero
    d = defender.hero

    battle = %Battle{
      type: Keyword.get(opts, :type, "pve"),
      attacker: a,
      attacker_id: a.id,
      defender: d,
      defender_id: d.id,
      attacker_player: a.player,
      attacker_player_id: a.player.id,
      defender_player: d.player,
      defender_player_id: d.player.id,
      initiator: a,
      initiator_id: a.id,
      initiator_player: a.player,
      initiator_player_id: a.player.id,
      turns: []
    }

    battle = if opts[:initiative] == :training, do: Core.determine_initiator(battle), else: battle
    battle = %{battle | initiator_id: battle.initiator.id, initiator_player_id: battle.initiator_player.id}

    %{
      battle: battle,
      starting: %{
        a.id => %{hp: attacker.hp, energy: attacker.energy},
        d.id => %{hp: defender.hp, energy: defender.energy}
      },
      rng: rng()
    }
  end

  def next_turn(duel, orders \\ %{auto: true}) do
    turn = Turns.build_turn(duel.battle, orders)

    if duel.battle.turns == [] do
      a = duel.starting[turn.attacker.hero_id]
      d = duel.starting[turn.defender.hero_id]

      %{
        turn
        | attacker: %{turn.attacker | current_hp: a.hp, current_mp: a.energy, starting_hp: a.hp, starting_mp: a.energy},
          defender: %{turn.defender | current_hp: d.hp, current_mp: d.energy, starting_hp: d.hp, starting_mp: d.energy}
      }
    else
      turn
    end
  end

  def step(%{battle: %{finished: true}} = duel, _), do: duel

  def step(duel, orders) do
    :rand.seed(duel.rng)
    turn = duel |> next_turn(orders) |> Processor.process_turn() |> Turns.serialize()
    turn = %{turn | battle: nil, orders: nil}
    turns = duel.battle.turns ++ [turn]
    finished = turn.attacker.current_hp <= 0 || turn.defender.current_hp <= 0 || length(turns) >= 100
    survivor = if finished, do: Enum.filter([turn.attacker, turn.defender], &(&1.current_hp > 0)), else: []

    winner =
      case survivor do
        [h] -> Enum.find([duel.battle.attacker, duel.battle.defender], &(&1.id == h.hero_id))
        _ -> nil
      end

    battle = %{
      duel.battle
      | turns: turns,
        finished: finished,
        winner: winner,
        winner_id: winner && winner.id,
        winner_player_id: winner && winner.player.id
    }

    %{duel | battle: battle, rng: :rand.export_seed()}
  end

  def result(duel) do
    turn = List.last(duel.battle.turns)

    resources =
      Map.new(
        [turn.attacker, turn.defender],
        &{&1.hero_id,
         %{
           hp: max(0, min(round(&1.total_hp), round(&1.current_hp))),
           energy: max(0, min(round(&1.total_mp), round(&1.current_mp)))
         }}
      )

    %{results: resources, battle: duel.battle, rng: duel.rng}
  end
end
