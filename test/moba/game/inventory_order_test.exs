defmodule Moba.Game.InventoryOrderTest do
  use Moba.DataCase

  test "slot order includes passives and sets only active battle priorities" do
    hero = equipped_hero()
    codes = ["sages_mask", "arcane_boots", "boots_of_speed", "dagon"]
    result = Game.reorder_inventory!(hero.player, hero, codes)
    assert result.inventory_order == codes
    assert result.item_order == ["arcane_boots", "dagon"]
    assert result.skill_order == hero.skill_order
    assert Enum.map(Game.inventory_items(Game.get_hero!(hero.id)), & &1.code) == codes

    assert Map.take(result, [:item_hp, :item_mp, :item_atk, :item_power, :item_armor, :item_speed, :gold]) ==
             Map.take(hero, [:item_hp, :item_mp, :item_atk, :item_power, :item_armor, :item_speed, :gold])
  end

  test "purchases, sales and transmutation retain the custom order of surviving items" do
    hero = equipped_hero()
    codes = ["sages_mask", "arcane_boots", "boots_of_speed", "dagon"]
    sorted = Game.reorder_inventory!(hero.player, hero, codes)
    bought = Game.buy_item!(sorted, Game.get_item_by_code!("chainmail"))
    assert bought.inventory_order == codes ++ ["chainmail"]
    assert bought.item_order == ["arcane_boots", "dagon"]

    # Reuse a stale hero to ensure the transaction reloads the saved layout.
    sold = Game.sell_item!(sorted, Game.get_item_by_code!("arcane_boots"))
    assert sold.inventory_order == ["sages_mask", "boots_of_speed", "dagon", "chainmail"]
    assert sold.item_order == ["dagon"]
    recipe = Enum.filter(sold.items, &(&1.rarity == "normal"))
    result = Game.transmute_item!(sold, recipe, Game.get_item_by_code!("tranquil_boots"))
    assert result.inventory_order == ["dagon", "tranquil_boots"]
    assert result.item_order == ["dagon", "tranquil_boots"]
  end

  test "foreign, duplicate, incomplete and stale inventory orders cannot be saved" do
    hero = equipped_hero()
    codes = Enum.map(hero.items, & &1.code)

    for invalid <- [tl(codes), List.duplicate(hd(codes), length(codes)), ["satanic" | tl(codes)], "not-an-order"] do
      Game.reorder_inventory!(hero.player, hero, invalid)
      assert Game.get_hero!(hero.id).inventory_order == []
    end

    Game.reorder_inventory!(create_player!(), hero, Enum.reverse(codes))
    assert Game.get_hero!(hero.id).inventory_order == []

    Game.buy_item!(hero, Game.get_item_by_code!("chainmail"))
    Game.reorder_inventory!(hero.player, hero, Enum.reverse(codes))
    assert Game.get_hero!(hero.id).inventory_order == []
    assert length(Game.get_hero!(hero.id).items) == 5
  end

  defp equipped_hero do
    Enum.reduce(["boots_of_speed", "dagon", "sages_mask", "arcane_boots"], create_base_hero(%{gold: 30_000}), fn code,
                                                                                                                 hero ->
      Game.buy_item!(hero, Game.get_item_by_code!(code))
    end)
  end
end
