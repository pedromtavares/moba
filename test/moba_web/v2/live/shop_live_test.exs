defmodule MobaWeb.V2.ShopLiveTest do
  use MobaWeb.ConnCase
  import Phoenix.LiveViewTest

  test "shelves inspect item details, buy once and sell from inventory", %{conn: conn} do
    hero = create_base_hero(%{gold: 10_000})
    Game.update_tutorial_step!(hero.player, 39)
    {:ok, view, _} = live(log_in_player(conn, player_id: hero.player_id), "/training")
    view |> element("#toggle-shop") |> render_click()

    assert has_element?(view, "#shop-modal[role=dialog][aria-modal=true][aria-labelledby=shop-title]")
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
    assert has_element?(view, "#shop-detail-description", item.description)
    assert has_element?(view, "#shop-detail .shop-stat[data-stat=speed]", "+#{item.base_speed}")
    view |> element("#buy-button") |> render_click()

    assert has_element?(view, "#shop-detail-name", item.name)
    assert has_element?(view, "#buy-button[disabled]", "Already in your inventory")
    refute has_element?(view, "#buy-button .ui-coins")
    refute has_element?(view, "#shop-purchase-hint")
    assert has_element?(view, "#shop-gold", "#{hero.gold - Game.item_price(item)}")
    assert has_element?(view, "#inventory", "1 / 6 slots")

    view |> element("#transmute-#{item.id}") |> render_click()
    assert has_element?(view, "#inventory .shop-shelf-label[aria-pressed=true]")
    refute has_element?(view, "#buy-button")
    view |> element("#sell-#{item.id}") |> render_click()
    assert Game.get_hero!(hero.id).items == []
    refute has_element?(view, "#sell-#{item.id}")
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
