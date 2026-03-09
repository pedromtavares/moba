defmodule MobaWeb.V2.TrainingLiveTest do
  use MobaWeb.ConnCase
  import Phoenix.LiveViewTest

  test "connected mount", %{conn: conn} do
    hero = create_base_hero()

    conn =
      conn
      |> log_in_user(hero.player.user)
      |> put_session(:player_id, hero.player_id)

    {:ok, _view, html} = live(conn, "/training")
    assert html =~ "MEDITATE"
  end

  test "guest with player_id can access /training", %{conn: conn} do
    hero = create_base_hero()

    conn =
      conn
      |> init_test_session(player_id: hero.player_id)

    {:ok, _view, html} = live(conn, "/training")
    assert html =~ "MEDITATE"
  end

  test "connected mount redirects if there is no pve hero", %{conn: conn} do
    player = create_player!(%{current_pve_hero_id: nil})
    user = Accounts.get_user!(player.user_id)

    conn =
      conn
      |> log_in_user(user)
      |> put_session(:player_id, player.id)

    live(conn, "/training") |> follow_redirect(conn, "/base")
  end

  test "league challenge starts a league battle and updates league progress", %{conn: conn} do
    hero =
      create_base_hero(%{
        league_tier: 0,
        league_step: 0,
        league_attempts: 0,
        pve_current_turns: 0,
        pve_total_turns: 15
      })

    conn =
      conn
      |> log_in_user(hero.player.user)
      |> put_session(:player_id, hero.player_id)

    {:ok, view, _html} = live(conn, "/training")
    assert has_element?(view, "#start-league-challenge")

    {:ok, _battle_view, html} =
      view
      |> element("#start-league-challenge")
      |> render_click()
      |> follow_redirect(conn)

    assert html =~ "Click to select a skill"

    updated_hero = Game.get_hero!(hero.id)
    battle = Engine.latest_battle(hero.id)

    assert updated_hero.league_step == 1
    assert updated_hero.league_attempts == 1
    assert battle.type == "league"
    assert battle.attacker_id == hero.id
  end

  test "buyback revives dead hero with enough gold", %{conn: conn} do
    hero = create_base_hero(%{pve_state: "dead", gold: 1_000, level: 10, total_gold_farm: 1_000})
    price = Game.buyback_price(hero)

    conn =
      conn
      |> log_in_user(hero.player.user)
      |> put_session(:player_id, hero.player_id)

    {:ok, view, _html} = live(conn, "/training")
    assert has_element?(view, "#buyback-hero")

    view |> element("#buyback-hero") |> render_click()

    updated_hero = Game.get_hero!(hero.id)
    assert updated_hero.pve_state == "alive"
    assert updated_hero.buybacks == 1
    assert updated_hero.gold == hero.gold - price
    assert updated_hero.total_gold_farm == hero.total_gold_farm - price
  end

  test "hero bar shop toggle is parent-owned on training", %{conn: conn} do
    hero = create_base_hero()

    conn =
      conn
      |> log_in_user(hero.player.user)
      |> put_session(:player_id, hero.player_id)

    {:ok, view, _html} = live(conn, "/training")

    assert has_element?(view, "#hero-bar .stats-group .text-danger[title*='Health:']")
    assert has_element?(view, "#hero-bar .stats-group .text-orange[title*='Speed:']")

    refute has_element?(view, "#shop-modal.d-block")

    view
    |> element("#hero-bar #toggle-shop")
    |> render_click()

    assert has_element?(view, "#shop-modal.d-block")
  end

  test "shop selection resets after buy and sell actions", %{conn: conn} do
    [first_item, second_item | _] = Enum.filter(Moba.cached_items(), &(&1.rarity == "normal"))
    hero = create_base_hero(%{gold: 10_000})

    conn =
      conn
      |> log_in_user(hero.player.user)
      |> put_session(:player_id, hero.player_id)

    {:ok, view, _html} = live(conn, "/training")

    view
    |> element("#hero-bar #toggle-shop")
    |> render_click()

    view
    |> element("#item-#{first_item.id}")
    |> render_click()

    view
    |> element("#buy-button")
    |> render_click()

    refute has_element?(view, "#buy-button")

    view
    |> element("#item-#{second_item.id}")
    |> render_click()

    view
    |> element("#buy-button")
    |> render_click()

    assert length(Game.get_hero!(hero.id).items) == 2

    view
    |> element("#transmute-#{first_item.id}")
    |> render_click()

    assert has_element?(view, "#sell-#{first_item.id}")

    view
    |> element("#sell-#{first_item.id}")
    |> render_click()

    refute has_element?(view, "#sell-#{first_item.id}")
    assert length(Game.get_hero!(hero.id).items) == 1
  end

  test "transmuting during the tutorial advances to the next step", %{conn: conn} do
    hero =
      create_base_hero(%{gold: 10_000})
      |> Game.buy_item!(Game.get_item_by_code!("boots_of_speed"))
      |> Game.buy_item!(Game.get_item_by_code!("sages_mask"))
      |> Game.buy_item!(Game.get_item_by_code!("chainmail"))

    player = Game.update_tutorial_step!(hero.player, 7)
    boots = Enum.find(hero.items, &(&1.code == "boots_of_speed"))
    mask = Enum.find(hero.items, &(&1.code == "sages_mask"))
    chainmail = Enum.find(hero.items, &(&1.code == "chainmail"))

    conn =
      conn
      |> log_in_user(player.user)
      |> put_session(:player_id, player.id)

    {:ok, view, _html} = live(conn, "/training")

    assert has_element?(view, "#tutorial-step-7[data-step='7']")

    view
    |> element("#hero-bar #toggle-shop")
    |> render_click()

    view
    |> element(".code-tranquil_boots")
    |> render_click()

    view
    |> element(".transmute-button")
    |> render_click()

    assert has_element?(view, "#tutorial-step-8[data-step='8']")

    view
    |> element("#transmute-#{boots.id}")
    |> render_click()

    view
    |> element("#transmute-#{mask.id}")
    |> render_click()

    view
    |> element("#transmute-#{chainmail.id}")
    |> render_click()

    view
    |> form("#shop form", %{
      "transmute_code" => "tranquil_boots",
      "recipe_codes" => ["boots_of_speed", "sages_mask", "chainmail"]
    })
    |> render_submit()

    assert has_element?(view, "#tutorial-step-9[data-step='9']")
  end

  test "roshan flow shows second-attempt messaging and still starts boss fight", %{conn: conn} do
    hero =
      create_base_hero(%{
        league_tier: Moba.master_league_tier(),
        league_step: 0,
        league_attempts: 0,
        pve_current_turns: 0,
        pve_total_turns: 0
      })
      |> Game.generate_boss!()

    boss = Game.get_hero!(hero.boss_id)
    Game.update_hero!(boss, %{league_attempts: 1, total_hp: div(boss.total_hp, 2)})

    conn =
      conn
      |> log_in_user(hero.player.user)
      |> put_session(:player_id, hero.player_id)

    {:ok, view, html} = live(conn, "/training")
    assert html =~ "Boss Fight"
    assert html =~ "one last time"
    assert has_element?(view, "#start-league-challenge")

    {:ok, _battle_view, battle_html} =
      view
      |> element("#start-league-challenge")
      |> render_click()
      |> follow_redirect(conn)

    assert battle_html =~ "Click to select a skill"

    battle = Engine.latest_battle(hero.id)
    detailed_battle = Engine.get_battle!(battle.id)
    assert battle.type == "league"
    assert detailed_battle.defender.bot_difficulty == "boss"
  end
end
