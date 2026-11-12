defmodule Moba.Game.ForgedItemsTest do
  use Moba.DataCase

  alias Moba.Game.Items
  alias Moba.Engine.Core.{Processor, Turns}

  test "a full build gains one slot's worth of equipment and selling the pair refunds the full price" do
    hero = equipped_hero(3_200)
    legendary = item("scythe_of_vyse")
    epic = item("soul_booster")

    forged = Items.forge_item!(hero.player, hero, legendary.code, epic.code)
    assert forged.gold == 0
    assert Items.forge_pairs(forged) == %{legendary.code => epic.code}
    assert forged.item_mp == hero.item_mp + epic.base_mp
    assert length(forged.items) == 7
    assert length(Game.inventory_items(forged)) == 6
    assert %{forged_epic: ^epic} = Enum.find(Game.inventory_items(forged), &(&1.code == legendary.code))
    assert legendary.code in forged.item_order
    refute epic.code in forged.item_order
    refute Game.can_buy_item?(forged, epic)

    assert Items.forge_item!(hero.player, hero, legendary.code, epic.code).gold == 0

    assert Items.forge_item!(hero.player, hero, "daedalus", "bloodstone") |> Items.forge_pairs() ==
             Items.forge_pairs(forged)

    sold = Game.sell_item!(hero, legendary)
    assert sold.gold == 8_000
    assert Items.forge_pairs(sold) == %{}
    assert length(sold.items) == 5
    refute epic.code in sold.item_order
  end

  test "forging uses owned Epics, preserves boots rules, and validates eligibility and inputs" do
    boots = item("boots_of_travel")
    phase_boots = item("phase_boots")
    hero = create_combat_hero(%{gold: 8_000}) |> Game.buy_item!(boots) |> Game.buy_item!(phase_boots)

    assert Items.forge_item!(hero.player, hero, boots.code, phase_boots.code) |> Items.forge_pairs() == %{}
    hero = Game.update_hero!(hero, %{finished_at: Timex.now()})
    assert Items.forge_item!(create_player!(), hero, boots.code, phase_boots.code) |> Items.forge_pairs() == %{}
    assert Items.forge_item!(hero.player, hero, boots.code, "missing") |> Items.forge_pairs() == %{}
    assert Items.forge_item!(hero.player, hero, boots.code, "sages_mask") |> Items.forge_pairs() == %{}
    assert Items.forge_item!(hero.player, hero, boots.code, "dagon") |> Items.forge_pairs() == %{}

    forged = Items.forge_item!(hero.player, hero, boots.code, phase_boots.code)
    assert forged.gold == 0
    assert forged.item_speed == hero.item_speed
    assert length(Game.inventory_items(forged)) == 1

    with_epic = Game.update_hero!(forged, %{gold: 2_400}) |> Game.buy_item!(item("dagon"))
    assert Game.sell_item!(with_epic, phase_boots).gold == 0

    assert Game.transmute_item!(with_epic, [phase_boots, item("dagon")], item("daedalus")) |> Items.forge_pairs() ==
             Items.forge_pairs(forged)

    swapped = Items.forge_item!(hero.player, with_epic, boots.code, "dagon")
    assert swapped.gold == 2_400
    assert Items.forge_pairs(swapped) == %{boots.code => "dagon"}
    refute Enum.any?(swapped.items, &(&1.code == phase_boots.code))
  end

  test "all six slots can be forged and each Epic belongs to a single slot" do
    hero = equipped_hero(19_200)
    first = Items.forge_item!(hero.player, hero, "boots_of_travel", "phase_boots")
    duplicate = Items.forge_item!(hero.player, hero, "daedalus", "phase_boots")
    assert duplicate.gold == first.gold
    assert Items.forge_pairs(duplicate) == %{"boots_of_travel" => "phase_boots"}

    other_pairs = %{
      "daedalus" => "assault_cuirass",
      "linkens_sphere" => "bkb",
      "orchid_malevolence" => "octarine_core",
      "scythe_of_vyse" => "soul_booster",
      "shivas_guard" => "bloodstone"
    }

    for {legendary, epic} <- other_pairs do
      Items.forge_item!(hero.player, hero, legendary, epic)
    end

    forged = Game.get_hero!(hero.id)
    assert forged.gold == 0
    assert length(forged.items) == 12
    assert Items.forge_pairs(forged) == Map.put(other_pairs, "boots_of_travel", "phase_boots")
    assert Enum.all?(Game.inventory_items(forged), &Map.has_key?(&1, :forged_epic))
    refute Game.can_buy_item?(forged, item("sages_mask"))

    codes = forged |> Game.inventory_items() |> Enum.map(& &1.code) |> Enum.reverse()
    reordered = Game.reorder_inventory!(hero.player, forged, codes)
    assert Enum.map(Game.inventory_items(reordered), & &1.code) == codes
    assert "orchid_malevolence" in reordered.item_order
    assert "scythe_of_vyse" in reordered.item_order
    assert Enum.all?(reordered.item_order, &(&1 in codes))
  end

  test "a battle keeps both original pairs and active item priorities after a swap" do
    hero = equipped_hero(6_400)
    Items.forge_item!(hero.player, hero, "scythe_of_vyse", "soul_booster")
    forged = Items.forge_item!(hero.player, hero, "shivas_guard", "bloodstone")
    battle = create_basic_battle(forged, create_combat_hero())

    swapped = Items.forge_item!(hero.player, forged, "scythe_of_vyse", "dagon")
    assert swapped.gold == 0
    assert Items.forge_pairs(swapped) == %{"scythe_of_vyse" => "dagon", "shivas_guard" => "bloodstone"}

    battle = Engine.get_battle!(battle.id)

    assert battle.loadouts[to_string(hero.id)]["forged_items"] == %{
             "scythe_of_vyse" => "soul_booster",
             "shivas_guard" => "bloodstone"
           }

    turn = Engine.build_turn(battle)
    battler = Enum.find([turn.attacker, turn.defender], &(&1.hero_id == hero.id))
    assert battler.total_mp == forged.total_mp + forged.item_mp

    assert %{forged_epic: %{code: "soul_booster"}} = Enum.find(battler.active_items, &(&1.code == "scythe_of_vyse"))
    assert %{forged_epic: %{code: "bloodstone"}} = Enum.find(battler.active_items, &(&1.code == "shivas_guard"))
    assert Enum.any?(battler.passive_items, &(&1.code == "soul_booster"))
    refute Enum.any?(battler.active_items, &(&1.code in ["soul_booster", "bloodstone", "dagon"]))
    refute Enum.any?(battler.item_order, &(&1.code == "soul_booster"))

    battle = Engine.continue_battle!(battle, %{skill: nil, item: item("scythe_of_vyse")})
    activated = Engine.get_battle!(battle.id).turns |> hd()
    assert %{forged_epic: %{code: "soul_booster"}} = activated.item
    assert activated.defender.stunned
    epic = activated.item.forged_epic
    restored = epic.base_amount

    assert Enum.any?(
             activated.attacker.effects,
             &match?(%{"resource" => "soul_booster", "key" => "mp_regen", "value" => ^restored}, &1)
           )

    assert activated.attacker.cooldowns == %{"scythe_of_vyse" => max(activated.item.cooldown, epic.cooldown) - 1}

    old_turn = %{activated | item_code: "scythe_of_vyse"}
    refute Map.has_key?(Turns.logged_item(old_turn, battle.loadouts), :forged_epic)

    old_cooldowns = %{"scythe_of_vyse" => 1, "soul_booster" => 3}
    old_attacker = %{old_turn.attacker | cooldowns: old_cooldowns, future_cooldowns: old_cooldowns}
    resumed = Turns.build_turn(%{battle | turns: [%{old_turn | attacker: old_attacker}]}, %{})
    assert resumed.defender.cooldowns == %{"scythe_of_vyse" => 3}
    assert resumed.defender.future_cooldowns == %{"scythe_of_vyse" => 3}
  end

  test "a forged activation spends combined Energy and uses one cooldown in automatic combat" do
    hero = equipped_hero(3_200)
    legendary = item("orchid_malevolence")
    epic = item("octarine_core")

    forged =
      Items.forge_item!(hero.player, hero, legendary.code, epic.code)
      |> Game.update_hero!(%{skill_order: [], item_order: [epic.code, legendary.code]})

    battle = create_basic_battle(forged, create_combat_hero())
    cost = legendary.mp_cost + epic.mp_cost

    short = Turns.build_turn(battle, %{skill: nil, item: legendary, attacker_initial_mp: cost - 1})
    refute Engine.can_use_resource?(short, legendary)
    refute Processor.process_turn(short).item

    turn = Turns.build_turn(battle, %{auto: true, attacker_initial_mp: cost})
    refute Engine.can_use_resource?(turn, epic)
    assert [%{code: "orchid_malevolence"}] = turn.attacker.item_order

    cooldowns = %{"satanic" => 5}
    turn = %{turn | attacker: %{turn.attacker | cooldowns: cooldowns, future_cooldowns: cooldowns}}
    activated = Processor.process_turn(turn)
    assert activated.item.code == legendary.code
    assert activated.defender.silenced
    assert activated.attacker.cooldowns == %{"satanic" => 2, legendary.code => epic.cooldown - 1}

    assert Enum.any?(
             activated.attacker.effects,
             &match?(%{"key" => :current_mp, "value" => value} when value == -cost, &1)
           )

    refute Engine.can_use_resource?(activated, legendary)
  end

  test "an active Epic can be cast through a passive Legendary's slot" do
    hero = equipped_hero(3_200)
    legendary = item("linkens_sphere")
    epic = item("dagon")
    silence = item("orchid_malevolence")
    opponent = create_combat_hero(%{gold: 4_800, total_hp: 1_000}) |> Game.buy_item!(silence)
    forged = Items.forge_item!(hero.player, hero, legendary.code, epic.code)
    battle = create_basic_battle(forged, opponent)
    turn = Turns.build_turn(battle, %{skill: nil, item: legendary})

    assert Engine.can_use_resource?(turn, legendary)
    refute Engine.can_use_resource?(turn, epic)
    assert Enum.any?(turn.attacker.passive_items, &(&1.code == legendary.code))
    activated = Processor.process_turn(turn)
    assert activated.item.code == legendary.code
    assert activated.defender.damage_type == "magic"
    assert activated.attacker.cooldowns == %{epic.code => epic.cooldown - 1}

    response =
      %{battle | turns: [Turns.serialize(activated)]}
      |> Turns.build_turn(%{skill: nil, item: silence})
      |> Processor.process_turn()

    assert response.item.code == silence.code
    assert response.defender.inneffectable
    refute response.defender.silenced
    assert response.defender.future_cooldowns[legendary.code] == legendary.cooldown
    assert response.defender.future_cooldowns[epic.code] == epic.cooldown - 1
  end

  defp equipped_hero(gold) do
    hero = create_combat_hero(%{gold: gold + 28_800, finished_at: Timex.now(), league_tier: 6})
    Enum.reduce(full_legendary_inventory(), hero, &Game.buy_item!(&2, &1))
  end

  defp item(code), do: Game.get_item_by_code!(code)
end
