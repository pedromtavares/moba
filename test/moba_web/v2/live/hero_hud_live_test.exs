defmodule MobaWeb.V2.HeroHudLiveTest do
  use MobaWeb.ConnCase
  import Phoenix.LiveViewTest

  test "spending the last skill point updates its rank and restores order editing", %{conn: conn} do
    hero = create_base_hero(%{level: 10, skill_levels_available: 1})
    skill = Enum.find(hero.skills, &(!&1.ultimate))
    conn = log_in_player(conn, player_id: hero.player_id)
    {:ok, view, _} = live(conn, "/hero/#{hero.id}")
    view |> element("#customize-hero") |> render_click()

    assert has_element?(view, "#hud-skill-points[role=status] strong", "+1")
    assert has_element?(view, "#hero-bar [phx-value-code='#{skill.code}'] .hud-upgrade-plus")
    refute has_element?(view, "#hero-bar #edit-button")

    view |> element("#hero-bar [phx-value-code='#{skill.code}']") |> render_click()

    updated = Game.get_hero!(hero.id)
    assert updated.skill_levels_available == 0
    assert Enum.find(updated.skills, &(&1.code == skill.code)).level == skill.level + 1
    assert has_element?(view, "#hero-bar .skill-levels[aria-label='#{skill.name} rank #{skill.level + 1} of 5']")
    refute has_element?(view, "#hud-skill-points")
    refute has_element?(view, "#hero-bar .hud-upgrade-plus")
    assert has_element?(view, "#hero-bar #edit-button")
  end

  test "HUD preserves order editing, shop and the mobile build toggle", %{conn: conn} do
    hero = create_base_hero()
    conn = log_in_player(conn, player_id: hero.player_id)
    {:ok, view, _} = live(conn, "/hero/#{hero.id}")
    view |> element("#customize-hero") |> render_click()

    view |> element("#hero-bar #edit-button") |> render_click()
    skill_order = hero.skill_order |> Enum.reverse() |> Enum.with_index(1) |> Map.new()

    view
    |> element("#hero-bar form")
    |> render_submit(%{"skill_order" => skill_order, "item_order" => %{}})

    assert Game.get_hero!(hero.id).skill_order == Enum.reverse(hero.skill_order)
    assert has_element?(view, "#hero-bar #edit-button")
    view |> element("#toggle-shop") |> render_click()
    assert has_element?(view, "#shop-modal.d-block")
    view |> element("#close-button[type=button][aria-label='Close shop']") |> render_click()
    assert has_element?(view, "#shop-modal.d-none")

    view |> element("#hero-bar [phx-click=show-build]") |> render_click()
    assert has_element?(view, "#hero-bar [phx-click=show-navigation]")
    view |> element("#hero-bar [phx-click=show-navigation]") |> render_click()
    assert has_element?(view, "#hero-bar [phx-click=show-build]")
  end

  test "shop X closes and reopens in every preview HUD", %{conn: conn} do
    hero = create_base_hero()
    Game.update_tutorial_step!(hero.player, 29)
    conn = log_in_player(conn, player_id: hero.player_id)

    for path <- ["/training", "/hero/#{hero.id}", "/arena/edit"] do
      {:ok, view, _} = live(conn, path)
      if path == "/hero/#{hero.id}", do: view |> element("#customize-hero") |> render_click()
      if path == "/arena/edit", do: render_click(view, "edit-hero", %{"id" => "#{hero.id}"})

      view |> element("#toggle-shop") |> render_click()
      assert has_element?(view, "#shop-modal.d-block")
      view |> element("#close-button") |> render_click()
      assert has_element?(view, "#shop-modal.d-none")
      view |> element("#toggle-shop") |> render_click()
      assert has_element?(view, "#shop-modal.d-block")
    end
  end

  test "experience and available upgrades render in the default HUD", %{conn: conn} do
    hero = create_base_hero(%{experience: 0, skill_levels_available: 2})
    conn = log_in_player(conn, player_id: hero.player_id)
    {:ok, preview, _} = live(conn, "/hero/#{hero.id}")
    preview |> element("#customize-hero") |> render_click()

    assert has_element?(preview, "#hero-bar [role=progressbar][aria-valuenow='0']")

    assert has_element?(
             preview,
             "#hero-bar .hud-experience-value",
             "0 / #{Game.xp_to_next_hero_level(hero.level + 1)} XP"
           )

    assert has_element?(preview, "#hud-skill-points strong", "+2")
    assert has_element?(preview, "#hero-bar .hud-experience")
  end

  test "cancel exits order editing without saving in every preview HUD", %{conn: conn} do
    hero = create_base_hero(%{gold: 10_000}) |> Game.buy_item!(alternate_item())
    conn = log_in_player(conn, player_id: hero.player_id)

    for path <- ["/training", "/hero/#{hero.id}", "/arena/edit"] do
      {:ok, view, _} = live(conn, path)
      if path == "/hero/#{hero.id}", do: view |> element("#customize-hero") |> render_click()
      if path == "/arena/edit", do: render_click(view, "edit-hero", %{"id" => "#{hero.id}"})

      view |> element("#hero-bar #edit-button") |> render_click()
      assert has_element?(view, "#hero-bar #save-button + #cancel-orders-button[type=button]")
      view |> element("#cancel-orders-button") |> render_click()

      assert has_element?(view, "#hero-bar #edit-button")
      refute has_element?(view, "#hero-bar select")
      refute has_element?(view, "#hero-bar #save-button")
      updated = Game.get_hero!(hero.id)
      assert updated.skill_order == hero.skill_order
      assert updated.item_order == hero.item_order

      view |> element("#hero-bar #edit-button") |> render_click()

      for {code, index} <- Enum.with_index(hero.skill_order, 1) do
        assert has_element?(view, "#hero-bar select[name='skill_order[#{code}]'] option[value='#{index}'][selected]")
      end
    end
  end

  test "dragging inventory saves its displayed order in Training and hero customization", %{conn: conn} do
    hero =
      Enum.reduce(["boots_of_speed", "dagon", "arcane_boots"], create_base_hero(%{gold: 30_000}), fn code, hero ->
        Game.buy_item!(hero, Game.get_item_by_code!(code))
      end)

    Game.update_tutorial_step!(hero.player, 39)
    conn = log_in_player(conn, player_id: hero.player_id)

    for path <- ["/training", "/hero/#{hero.id}"] do
      {:ok, view, _} = live(conn, path)
      if path != "/training", do: view |> element("#customize-hero") |> render_click()
      current = Game.get_hero!(hero.id)
      codes = current |> Game.inventory_items() |> Enum.map(& &1.code) |> Enum.reverse()
      assert has_element?(view, "#hero-inventory[phx-hook=InventoryOrder][data-reorderable=true]")
      render_click(view, "reorder-items", %{"codes" => codes, "hero_id" => to_string(hero.id)})
      assert Game.get_hero!(hero.id).inventory_order == codes
      assert Game.get_hero!(hero.id).skill_order == current.skill_order

      for {code, position} <- Enum.with_index(codes, 1) do
        assert has_element?(view, "#hero-inventory > :nth-child(#{position})[data-item-code=#{code}]")
      end

      {:ok, reloaded, _} = live(conn, path)
      if path != "/training", do: reloaded |> element("#customize-hero") |> render_click()
      assert has_element?(reloaded, "#hero-inventory > :first-child[data-item-code=#{hd(codes)}]")
    end
  end

  test "inventory reorder rejects a foreign hero and requires hero customization to be open", %{conn: conn} do
    hero = create_base_hero(%{gold: 10_000}) |> Game.buy_item!(alternate_item())
    payload = %{"codes" => [alternate_item().code], "hero_id" => to_string(hero.id)}
    {:ok, owner, _} = live(log_in_player(conn, player_id: hero.player_id), "/hero/#{hero.id}")
    render_click(owner, "reorder-items", payload)
    assert Game.get_hero!(hero.id).inventory_order == []
    {:ok, visitor, _} = live(log_in_player(conn, player_id: create_player!().id), "/hero/#{hero.id}")
    render_click(visitor, "reorder-items", payload)
    assert Game.get_hero!(hero.id).inventory_order == []

    owner |> element("#customize-hero") |> render_click()
    render_click(owner, "reorder-items", %{payload | "hero_id" => "0"})
    assert Game.get_hero!(hero.id).inventory_order == []
  end
end
