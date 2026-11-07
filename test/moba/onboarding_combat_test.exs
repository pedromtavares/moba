defmodule Moba.OnboardingCombatTest do
  use Moba.DataCase, async: true
  alias Moba.Engine.Core.{Processor, Turns}
  alias Moba.Engine.Schema.Battle
  alias Moba.Game.Training.{Combat, Loadouts}
  import Test.TeamHelper

  test "every avatar's solo and roster defaults prioritize its active ultimate without changing display order" do
    player = create_player!()
    catalog = Loadouts.catalog()

    for avatar <- catalog.avatars do
      build = Game.Builds.training_build_for(avatar)
      solo = Game.Heroes.create!(%{name: avatar.name}, player, avatar, build.skills) |> then(&Game.get_hero!(&1.id))
      roster = Loadouts.build_loadout(catalog, avatar, :radiant, 1, 1200)
      active = Enum.reject(roster.hero.skills, & &1.passive)
      expected = if avatar.ultimate.passive, do: hd(active).code, else: avatar.ultimate.code
      assert hd(solo.skill_order) == expected, "solo #{avatar.code}"
      assert hd(roster.hero.skill_order) == expected, "roster #{avatar.code}"
      assert List.last(roster.hero.skills).ultimate
      assert Enum.all?(roster.hero.skill_order, fn code -> Enum.find(active, &(&1.code == code)) end)
    end
  end

  test "actual newly drafted teams save ultimate-first priorities and retain them through persistence" do
    {scope, player} = team_account(0)
    record = team_run(scope, player)
    run = Game.TeamRuns.state(Game.TeamRuns.get!(scope, record.id))

    for unit <- Game.TeamTraining.team(run) do
      ultimate = Enum.find(unit.hero.skills, & &1.ultimate)
      if !ultimate.passive, do: assert(hd(unit.hero.skill_order) == ultimate.code)
      normals = Enum.reject(unit.hero.skills, &(&1.ultimate || &1.passive))
      assert Enum.drop(unit.hero.skill_order, if(ultimate.passive, do: 0, else: 1)) == Enum.map(normals, & &1.code)
    end
  end

  test "the default opening party preselects and automatically casts its ultimate with starter boots" do
    catalog = Loadouts.catalog()

    for code <- ~w(juggernaut lina tusk) do
      avatar = Enum.find(catalog.avatars, &(&1.code == code))
      own = Loadouts.build_loadout(catalog, avatar, :radiant, 1, 1200)
      own = %{own | hero: %{own.hero | pve_tier: 0}}
      enemy = Loadouts.build_loadout(catalog, Enum.find(catalog.avatars, &(&1.code == "lina")), :dire, 1001)
      duel = Combat.new_duel(own, enemy)
      turn = Combat.next_turn(duel, %{auto: true})
      assert Engine.preselected_skill(turn).code == avatar.ultimate.code
      assert Processor.process_turn(turn).skill.code == avatar.ultimate.code
      expected_boots = if avatar.role == "nuker", do: "tranquil_boots", else: "arcane_boots"
      assert hd(own.inventory).item.code == expected_boots
    end
  end

  test "selection respects cooldown, energy, custom priorities and forced continuations" do
    turn = bot_turn("pve", 1)
    ultimate = hd(turn.attacker.skill_order)
    normal = Enum.at(turn.attacker.skill_order, 1)
    assert Engine.preselected_skill(turn).code == ultimate.code
    blocked = put_in(turn.attacker.cooldowns[ultimate.code], 0)
    assert Engine.preselected_skill(blocked).code == normal.code
    empty = put_in(turn.attacker.current_mp, 0)
    assert Engine.preselected_skill(empty) == nil
    forced = put_in(empty.attacker.double_skill, ultimate)
    assert Engine.preselected_skill(forced).code == ultimate.code
    custom = put_in(turn.attacker.skill_order, [normal, ultimate])
    assert Engine.preselected_skill(custom).code == normal.code
    assert Processor.process_turn(custom).skill.code == normal.code
  end

  test "beginner solo targets can cast a ready ultimate even with another spell available" do
    turn = bot_turn("pve", 0)
    assert hd(turn.attacker.skill_order).ultimate
    assert Processor.process_turn(turn).skill.code == "laguna_blade"
    assert hd(turn.battle.defender.skill_order) == "laguna_blade"
  end

  test "beginner roster targets can cast a ready ultimate" do
    turn = bot_turn("pve", 0)
    own = %{hero: %{turn.battle.attacker | player: %Game.Schema.Player{id: -1}}, hp: 10_000, energy: 500}
    bot = %{hero: %{turn.battle.defender | player: %Game.Schema.Player{id: -2}}, hp: 10_000, energy: 500}
    duel = Combat.new_duel(own, bot)

    battle = %{
      duel.battle
      | initiator: bot.hero,
        initiator_id: bot.hero.id,
        initiator_player: bot.hero.player,
        initiator_player_id: -2
    }

    played = Combat.step(%{duel | battle: battle}, %{auto: true})
    assert hd(played.battle.turns).skill_code == "laguna_blade"
  end

  test "beginner target bots retain passive ultimate effects" do
    turn = bot_turn("pve", 0)
    coup = %{Game.get_current_skill!("coup", 1) | roll_number: 101}
    attacker = %{turn.attacker | passive_skills: [coup], skill_order: []}
    result = Processor.process_turn(%{turn | attacker: attacker})
    assert result.skill.code == "basic_attack"
    assert result.defender.armor < turn.defender.base_armor
  end

  test "beginner targets fall back to other skills if their ultimate is unavailable" do
    turn = bot_turn("pve", 0)
    blocked = put_in(turn.attacker.cooldowns["laguna_blade"], 2)
    assert Processor.process_turn(blocked).skill.code == "lightning_bolt"
    exhausted = put_in(turn.attacker.current_mp, 0)
    assert Processor.process_turn(exhausted).skill.code == "basic_attack"
  end

  test "league challenges, veteran targets and PvP retain bot ultimate casts" do
    for {type, tier} <- [{"league", 0}, {"pve", 1}, {"duel", 0}, {"match", 0}] do
      turn = bot_turn(type, tier)
      assert Processor.process_turn(turn).skill.code == "laguna_blade", "#{type}, tier #{tier}"
    end
  end

  defp bot_turn(type, tier) do
    player = create_player!(%{pve_tier: tier})
    avatar = Game.get_avatar_by_code!("lina")
    normal = Game.get_current_skill!("lightning_bolt", 1)
    passives = Enum.map(~w(feast jinada), &Game.get_current_skill!(&1, 1))
    skills = [normal | passives]

    own =
      Game.Heroes.create!(%{name: "Player", total_hp: 10_000, total_mp: 500}, player, avatar, skills)
      |> then(&Game.get_hero!(&1.id))

    bot =
      Game.Heroes.create!(
        %{
          name: "Bot",
          total_hp: 10_000,
          total_mp: 500,
          bot_difficulty: "weak",
          skill_order: ~w(laguna_blade lightning_bolt)
        },
        nil,
        avatar,
        skills
      )
      |> then(&Game.get_hero!(&1.id))

    %Battle{
      type: type,
      attacker: own,
      attacker_id: own.id,
      attacker_player: player,
      attacker_player_id: player.id,
      defender: bot,
      defender_id: bot.id,
      defender_player: nil,
      defender_player_id: nil,
      initiator: bot,
      initiator_id: bot.id,
      initiator_player: nil,
      initiator_player_id: nil,
      turns: []
    }
    |> Turns.build_turn(%{auto: true})
  end
end
