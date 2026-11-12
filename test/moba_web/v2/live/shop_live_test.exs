defmodule MobaWeb.V2.ShopLiveTest do
  use MobaWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  test "finished hero customization forges, displays, swaps and sells multiple pairs independently", %{conn: conn} do
    hero = create_base_hero(%{gold: 35_200, finished_at: Timex.now(), league_tier: 6})
    hero = Enum.reduce(full_legendary_inventory(), hero, &Game.buy_item!(&2, &1))
    active_hero = create_base_hero(%{}, Game.get_player!(hero.player_id))
    refute active_hero.id == hero.id
    legendary = Game.get_item_by_code!("scythe_of_vyse")
    second_legendary = Game.get_item_by_code!("orchid_malevolence")

    {:ok, view, _} = live(log_in_player(conn, player_id: hero.player_id), "/hero/#{hero.id}")
    view |> element("#customize-hero") |> render_click()
    view |> element("#inventory-#{legendary.id}") |> render_click()
    view |> element("#start-forge") |> render_click()
    assert has_element?(view, "#shop-title #forge-picker-title", "Choose an Epic")
    assert has_element?(view, "#forge-picker[aria-labelledby=forge-picker-title]")
    assert has_element?(view, ".shop-forge-socket.is-empty")
    assert has_element?(view, "#finish-forge[disabled]", "Forge")
    refute has_element?(view, "#shop-forge-form select")
    view |> element("#forge-epic-soul_booster") |> render_click()
    assert has_element?(view, "#forge-epic-soul_booster[aria-pressed=true]", "3200 gold")
    assert has_element?(view, "#forge-preview-soul_booster")
    assert has_element?(view, "#shop-detail .shop-eyebrow", "Forged Legendary")
    assert has_element?(view, "#shop-detail-description .forged-item-tooltip-component", "Soul Booster")
    assert has_element?(view, "#finish-forge", "Forge · 3200 gold")
    assert Game.get_hero!(hero.id).gold == 6_400
    view |> form("#shop-forge-form") |> render_submit()

    assert has_element?(view, "#shop-gold", "3200")
    assert has_element?(view, "#shop-modal.d-block")
    assert has_element?(view, "#inventory", "6 / 6 slots")
    assert has_element?(view, "#inventory-#{legendary.id}[data-rarity=forged-legendary] .forged-item-inset")
    assert has_element?(view, "#start-forge", "Swap Epic")
    refute has_element?(view, "#shop-inventory-order [data-item-code=soul_booster]")

    view |> element("#inventory-#{second_legendary.id}") |> render_click()
    view |> element("#start-forge") |> render_click()
    assert has_element?(view, "#forge-epic-soul_booster[disabled]", "Already forged")
    view |> element("#forge-epic-octarine_core") |> render_click()
    assert has_element?(view, "#shop-detail-description [data-kind=energy]", "25 Energy")
    assert has_element?(view, "#shop-detail-description [data-kind=cooldown]", "6 turns")
    view |> form("#shop-forge-form") |> render_submit()
    assert Game.get_hero!(hero.id).gold == 0
    assert has_element?(view, "#inventory", "6 / 6 slots")
    assert has_element?(view, "#inventory-#{second_legendary.id}[data-rarity=forged-legendary]")

    epic = Game.get_item_by_code!("soul_booster")
    second_epic = Game.get_item_by_code!("octarine_core")
    battle = create_basic_battle(Game.get_hero!(hero.id), create_combat_hero())
    {:ok, battle_view, _} = live(log_in_player(conn, player_id: hero.player_id), "/battles/#{battle.id}")
    assert has_element?(battle_view, ".forged-battle-slot #attacker-item-#{legendary.id}")
    assert has_element?(battle_view, ".forged-battle-slot #attacker-item-#{second_legendary.id}")
    refute has_element?(battle_view, "#attacker-item-#{epic.id}, #attacker-item-#{second_epic.id}")
    refute has_element?(battle_view, ".forged-battle-slot [aria-keyshortcuts^='Shift']")

    html = battle_view |> render() |> LazyHTML.from_fragment()
    assert Enum.count(LazyHTML.query(html, ".forged-battle-slot .item-img.can-use")) == 2

    assert has_element?(battle_view, "#stage-build-left-item-#{legendary.id}[title*='Forged Legendary']")
    assert has_element?(battle_view, ".stage-build-items [data-build-code=scythe_of_vyse] .forged-item-inset")
    refute has_element?(battle_view, ".stage-build-items .forged-item-inset [data-build-cooldown]")

    view |> element("#close-button") |> render_click()
    render_click(view, "start-edit")
    assert has_element?(view, "select[name='item_order[scythe_of_vyse]']")
    refute has_element?(view, "select[name='item_order[soul_booster]']")
    render_click(view, "cancel-edit")

    view |> element("#inventory-#{legendary.id}") |> render_click()
    view |> element("#start-forge") |> render_click()
    view |> element("#forge-epic-bloodstone") |> render_click()
    assert has_element?(view, "#finish-forge", "Swap Epic · free")
    view |> element("#cancel-forge") |> render_click()
    refute has_element?(view, "#forge-picker")
    assert has_element?(view, "#shop-detail-description .forged-item-tooltip-component", "Soul Booster")

    view |> element("#start-forge") |> render_click()
    view |> element("#forge-epic-bloodstone") |> render_click()
    view |> form("#shop-forge-form") |> render_submit()
    assert has_element?(view, "#shop-detail-description .forged-item-tooltip-component", "Bloodstone")

    view |> element("#sell-#{legendary.id}") |> render_click()
    assert has_element?(view, "#shop-gold", "8000")
    assert has_element?(view, "#inventory", "5 / 6 slots")
    assert Game.get_hero!(hero.id) |> Game.Items.forge_pairs() == %{"orchid_malevolence" => "octarine_core"}
  end

  test "the detail panel shares item tooltip descriptions, colored effects, and timing icons", %{conn: conn} do
    hero = create_base_hero(%{gold: 10_000})
    Game.update_tutorial_step!(hero.player, 39)
    {:ok, view, _} = live(log_in_player(conn, player_id: hero.player_id), "/training")
    view |> element("#toggle-shop") |> render_click()

    for code <- ["tranquil_boots", "vanguard", "satanic", "octarine_core"] do
      item = Game.get_item_by_code!(code)
      content = Game.ItemDescriptions.describe(item)
      view |> element("#item-#{item.id}") |> render_click()

      assert has_element?(view, "#shop-detail .item-tooltip[data-item-code='#{code}']")
      assert has_element?(view, "#shop-detail .skill-tooltip-summary", content.summary)
      refute has_element?(view, "#shop-detail .skill-tooltip-heading, #shop-detail .shop-item-timing")

      for effect <- content.effects do
        row = "#shop-detail [data-effect='#{effect.key}'][data-tone='#{effect.tone}']"
        assert has_element?(view, "#{row} dt .skill-tooltip-effect-icon.ui-icon")
        assert has_element?(view, "#{row} dt", effect.label)
        assert has_element?(view, "#{row} dd strong")
      end

      if item.active do
        assert has_element?(view, "#shop-detail [data-kind=energy] .ui-bolt")
        assert has_element?(view, "#shop-detail [data-kind=cooldown] .ui-clock")
      end

      assert has_element?(view, "#buy-button")
    end

    item = Game.get_item_by_code!("vanguard")
    view |> element("#item-#{item.id}") |> render_click()
    assert has_element?(view, "#shop-detail [data-effect=chance] strong", "#{item.roll_number}%")
  end

  test "shelves inspect item details, buy once and sell from inventory", %{conn: conn} do
    hero = create_base_hero(%{gold: 10_000})
    Game.update_tutorial_step!(hero.player, 39)
    {:ok, view, _} = live(log_in_player(conn, player_id: hero.player_id), "/training")
    view |> element("#toggle-shop") |> render_click()

    assert has_element?(view, "#shop-modal[role=dialog][aria-modal=true][aria-labelledby=shop-title]")
    assert has_element?(view, ".shop-shelves > #inventory:first-child.is-current")
    assert has_element?(view, "#shop-category-inventory[aria-pressed=true]")
    assert has_element?(view, ".shop-keyboard-hint", "SPACE")
    assert has_element?(view, "#toggle-shop .hud-shop-hotkey", "F")
    assert has_element?(view, "#inventory", "0 / 6 slots")

    for {rarity, boots} <- [
          {"normal", "boots_of_speed"},
          {"rare", "tranquil_boots"},
          {"epic", "phase_boots"},
          {"legendary", "boots_of_travel"}
        ] do
      assert has_element?(view, "#shop-shelf-#{rarity} .shop-tile:first-child[phx-value-code=#{boots}]")
    end

    assert has_element?(view, ".normal-items .code-boots_of_speed[data-toggle=tooltip][title]")
    assert has_element?(view, "#shop-shelf-normal .shop-tile:nth-child(2)[phx-value-code=sages_mask]")
    assert has_element?(view, "#shop-shelf-rare .shop-tile:nth-child(2)[phx-value-code=arcane_boots]")

    view |> element("#inventory .shop-shelf-label") |> render_click()
    assert has_element?(view, "#shop-detail", "Six slots.")
    refute has_element?(view, "#buy-button")

    view |> element("#shop-shelf-legendary .shop-shelf-label") |> render_click()
    assert has_element?(view, "#shop-shelf-legendary .shop-shelf-label[aria-pressed=true]")
    assert has_element?(view, "#shop-detail[data-rarity=legendary]")

    item = base_item()
    view |> element("#item-#{item.id}") |> render_click()
    assert has_element?(view, "#shop-detail-name", item.name)

    assert has_element?(
             view,
             "#shop-detail-description .skill-tooltip-notes",
             hd(Game.ItemDescriptions.describe(item).notes)
           )

    assert has_element?(view, "#shop-detail .item-tooltip-stat[data-stat=base_speed]", "+#{item.base_speed}")
    view |> element("#buy-button") |> render_click()

    assert has_element?(view, "#shop-detail-name", item.name)
    assert has_element?(view, "#buy-button[disabled]", "Already in your inventory")
    refute has_element?(view, "#buy-button .ui-coins")
    refute has_element?(view, "#shop-purchase-hint")
    assert has_element?(view, "#shop-gold", "#{hero.gold - Game.item_price(item)}")
    assert has_element?(view, "#inventory", "1 / 6 slots")
    assert has_element?(view, "#hero-inventory [data-item-code='#{item.code}'][data-rarity='#{item.rarity}']")
    assert has_element?(view, "#shop-inventory-order [data-item-code='#{item.code}'][data-rarity='#{item.rarity}']")

    view |> element("#transmute-#{item.id}") |> render_click()
    assert has_element?(view, "#inventory .shop-shelf-label[aria-pressed=true]")
    refute has_element?(view, "#buy-button")
    view |> element("#sell-#{item.id}") |> render_click()
    assert Game.get_hero!(hero.id).items == []
    refute has_element?(view, "#sell-#{item.id}")
  end

  test "opening the shop starts with the first owned item", %{conn: conn} do
    hero = create_base_hero(%{gold: 10_000}) |> Game.buy_item!(base_item())
    Game.update_tutorial_step!(hero.player, 39)
    {:ok, view, _} = live(log_in_player(conn, player_id: hero.player_id), "/training")
    view |> element("#toggle-shop") |> render_click()
    assert has_element?(view, ".shop-shelves > #inventory:first-child.is-current")
    assert has_element?(view, "#shop-detail-name", base_item().name)
    assert has_element?(view, "#sell-#{base_item().id}")
    refute has_element?(view, "#buy-button")
  end

  test "HUD inventory clicks open the shop on that owned item in training and customization", %{conn: conn} do
    hero =
      Enum.reduce(["boots_of_speed", "sages_mask", "chainmail"], create_base_hero(%{gold: 10_000}), fn code, hero ->
        Game.buy_item!(hero, Game.get_item_by_code!(code))
      end)

    Game.update_tutorial_step!(hero.player, 39)
    conn = log_in_player(conn, player_id: hero.player_id)
    item = Game.get_item_by_code!("sages_mask")
    result = Game.get_item_by_code!("tranquil_boots")

    for path <- ["/training", "/hero/#{hero.id}"] do
      {:ok, view, _} = live(conn, path)
      if path != "/training", do: view |> element("#customize-hero") |> render_click()
      view |> element("#inventory-#{item.id}") |> render_click()
      assert has_element?(view, "#shop-modal.d-block")
      assert has_element?(view, "#shop-detail-name", item.name)
      assert has_element?(view, "#sell-#{item.id}")
      refute has_element?(view, "#buy-button")
      refute has_element?(view, ".shop-heading .shop-eyebrow")

      view |> element("#item-#{result.id}") |> render_click()
      view |> element("#start-transmute") |> render_click()
      assert has_element?(view, "#shop-transmute-form")
      view |> element("#inventory-#{item.id}") |> render_click()
      assert has_element?(view, "#shop-modal.d-block")
      assert has_element?(view, "#shop-detail-name", item.name)
      assert has_element?(view, "#sell-#{item.id}")
      refute has_element?(view, "#shop-transmute-form")
    end
  end

  test "transmute keeps the result visible and requires a complete recipe", %{conn: conn} do
    hero =
      Enum.reduce(["boots_of_speed", "sages_mask", "chainmail"], create_base_hero(%{gold: 10_000}), fn code, hero ->
        Game.buy_item!(hero, Game.get_item_by_code!(code))
      end)

    Game.update_tutorial_step!(hero.player, 39)
    {:ok, view, _} = live(log_in_player(conn, player_id: hero.player_id), "/training")
    view |> element("#toggle-shop") |> render_click()
    result = Game.get_item_by_code!("tranquil_boots")
    view |> element("#item-#{result.id}") |> render_click()
    view |> element("#start-transmute") |> render_click()
    assert has_element?(view, "#shop-detail-name", result.name)
    assert has_element?(view, "#finish-transmute[disabled]")
    refute has_element?(view, "#buy-button")

    first = hd(hero.items)
    view |> element("#transmute-#{first.id}") |> render_click()
    assert has_element?(view, "#transmute-#{first.id}[aria-disabled=true][aria-pressed=true]")
    assert has_element?(view, "#recipe-#{first.id}")
    assert has_element?(view, "#finish-transmute[disabled]")
    view |> element("#cancel-transmute") |> render_click()
    refute has_element?(view, "#shop-transmute-form")
    assert has_element?(view, "#shop-detail-name", result.name)

    view |> element("#start-transmute") |> render_click()
    for item <- hero.items, do: view |> element("#transmute-#{item.id}") |> render_click()
    assert has_element?(view, "#finish-transmute:not([disabled])")
    view |> form("#shop-transmute-form") |> render_submit()

    assert Enum.map(Game.get_hero!(hero.id).items, & &1.code) == [result.code]
    assert has_element?(view, "#shop-detail-name", result.name)
    assert has_element?(view, "#inventory", "1 / 6 slots")
    assert has_element?(view, "#hero-inventory [data-item-code='#{result.code}'][data-rarity=rare]")
    assert has_element?(view, "#shop-inventory-order [data-item-code='#{result.code}'][data-rarity=rare]")
    refute has_element?(view, "#shop-transmute-form")
  end

  test "unaffordable items explain their cost and transmute needs the correct rarity", %{conn: conn} do
    hero =
      Enum.reduce(["boots_of_speed", "sages_mask", "chainmail"], create_base_hero(%{gold: 1_200}), fn code, hero ->
        Game.buy_item!(hero, Game.get_item_by_code!(code))
      end)

    Game.update_tutorial_step!(hero.player, 39)
    {:ok, view, _} = live(log_in_player(conn, player_id: hero.player_id), "/training")
    view |> element("#toggle-shop") |> render_click()
    item = Game.get_item_by_code!("silver_edge")
    view |> element("#item-#{item.id}") |> render_click()
    assert has_element?(view, "#buy-button[disabled]")
    assert has_element?(view, "#shop-purchase-hint", "#{Game.item_price(item)} more gold needed")
    assert has_element?(view, "#start-transmute[disabled]")

    rare = Game.get_item_by_code!("tranquil_boots")
    view |> element("#item-#{rare.id}") |> render_click()
    assert has_element?(view, "#buy-button[disabled]")
    assert has_element?(view, "#start-transmute:not([disabled])")

    view |> element(".shop-inspect-tabs [phx-value-tab=effects]") |> render_click()
    assert has_element?(view, ".shop-item-description[data-detail-tab=effects]")
    view |> element(".shop-inspect-tabs [phx-value-tab=overview]") |> render_click()
    assert has_element?(view, ".shop-item-description[data-detail-tab=overview]")
  end

  test "shop and HUD share the saved order while open, preserving item selection and recipes", %{conn: conn} do
    hero =
      Enum.reduce(["boots_of_speed", "sages_mask", "chainmail", "dagon"], create_base_hero(%{gold: 20_000}), fn code,
                                                                                                                hero ->
        Game.buy_item!(hero, Game.get_item_by_code!(code))
      end)

    Game.update_tutorial_step!(hero.player, 39)
    conn = log_in_player(conn, player_id: hero.player_id)

    for path <- ["/training", "/hero/#{hero.id}"] do
      {:ok, view, _} = live(conn, path)
      if path != "/training", do: view |> element("#customize-hero") |> render_click()
      view |> element("#toggle-shop") |> render_click()
      assert has_element?(view, "#hero-inventory[data-reorderable=true]")
      assert has_element?(view, "#shop-inventory-order[data-reorderable=true][phx-hook=InventoryOrder]")

      boots = Game.get_item_by_code!("boots_of_speed")
      view |> element("#transmute-#{boots.id}") |> render_click()
      codes = ["sages_mask", "boots_of_speed", "dagon", "chainmail"]
      render_click(view, "reorder-items", %{"hero_id" => to_string(hero.id), "codes" => codes})
      assert has_element?(view, "#sell-#{boots.id}")

      for {code, index} <- Enum.with_index(codes, 1) do
        for root <- ["hero-inventory", "shop-inventory-order"] do
          assert has_element?(view, "##{root} > :nth-child(#{index})[data-item-code=#{code}]")
        end
      end

      result = Game.get_item_by_code!("tranquil_boots")
      view |> element("#item-#{result.id}") |> render_click()
      view |> element("#start-transmute") |> render_click()
      view |> element("#transmute-#{boots.id}") |> render_click()
      refute has_element?(view, "#transmute-#{boots.id}[disabled]")
      render_click(view, "reorder-items", %{"hero_id" => to_string(hero.id), "codes" => Enum.reverse(codes)})
      assert has_element?(view, "#shop-transmute-form")
      assert has_element?(view, "#recipe-#{boots.id}")
      assert has_element?(view, "#finish-transmute[disabled]")
      assert Game.get_hero!(hero.id).inventory_order == Enum.reverse(codes)
      assert has_element?(view, "#shop-modal.d-block")
    end
  end
end
