defmodule MobaWeb.V2.HeroHudLiveTest do
  use MobaWeb.ConnCase
  import Phoenix.LiveViewTest

  test "spending the last skill point updates its rank and restores order editing", %{conn: conn} do
    hero = create_base_hero(%{level: 10, skill_levels_available: 1})
    skill = Enum.find(hero.skills, &(!&1.ultimate))
    conn = init_test_session(conn, player_id: hero.player_id)
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
    conn = init_test_session(conn, player_id: hero.player_id)
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
    conn = init_test_session(conn, player_id: hero.player_id)

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
    conn = init_test_session(conn, player_id: hero.player_id)
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
    conn = init_test_session(conn, player_id: hero.player_id)

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
end
