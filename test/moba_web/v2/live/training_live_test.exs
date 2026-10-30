defmodule MobaWeb.V2.TrainingLiveTest do
  use MobaWeb.ConnCase
  import Phoenix.LiveViewTest

  test "orders all-hard targets by level and preserves mixed ordering", %{conn: conn} do
    hero = create_base_hero(%{pve_tier: 4, pve_current_turns: 3})

    for level <- [22, 20, 21] do
      defender = create_base_hero() |> Game.update_hero!(%{level: level, total_gold_farm: level * 100})
      Moba.Repo.insert!(%Game.Schema.Target{attacker_id: hero.id, defender_id: defender.id, difficulty: "strong"})
    end

    conn = init_test_session(conn, player_id: hero.player_id)
    original_targets = Game.list_targets(hero)
    expected = original_targets |> Enum.sort_by(& &1.defender.level) |> Enum.map(&"gank-#{&1.id}")
    original_order = Enum.map(original_targets, &"gank-#{&1.id}")
    refute expected == original_order

    {:ok, preview, _} = live(conn, "/training")
    assert target_button_ids(preview) == expected

    hd(original_targets)
    |> Game.Schema.Target.changeset(%{difficulty: "moderate"})
    |> Moba.Repo.update!()

    mixed_order = Game.list_targets(hero) |> Enum.map(&"gank-#{&1.id}")
    {:ok, mixed, _} = live(conn, "/training")
    assert target_button_ids(mixed) == mixed_order
  end

  defp target_button_ids(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(".targets button[id^='gank-']")
    |> LazyHTML.attribute("id")
  end

  test "connected mount", %{conn: conn} do
    hero = create_base_hero()

    conn =
      conn
      |> log_in_user(hero.player.user)
      |> put_session(:player_id, hero.player_id)

    {:ok, view, _html} = live(conn, "/training")
    assert has_element?(view, "#current-training-rank")
  end

  test "guest with player_id can access /training", %{conn: conn} do
    hero = create_base_hero()

    conn =
      conn
      |> init_test_session(player_id: hero.player_id)

    {:ok, view, _html} = live(conn, "/training")
    assert has_element?(view, "#current-training-rank")
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

    assert html =~ "Make your first move"

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

  test "preview death panel shows the gold cost and revives the hero", %{conn: conn} do
    hero = create_base_hero(%{pve_state: "dead", gold: 1_000, level: 10, total_gold_farm: 1_000})
    price = Game.buyback_price(hero)
    conn = conn |> log_in_user(hero.player.user) |> put_session(:player_id, hero.player_id)
    {:ok, view, _} = live(conn, "/training")

    assert has_element?(view, "#death-panel[aria-labelledby=death-title]")
    assert has_element?(view, "#death-gold-cost", "#{price}")
    assert has_element?(view, "#buyback-hero:not([disabled])")
    assert has_element?(view, "#restart-hero[data-confirm]")
    assert has_element?(view, "#death-new-hero[href='/invoke']")
    view |> element("#buyback-hero") |> render_click()

    refute has_element?(view, "#death-panel")
    assert Game.get_hero!(hero.id).pve_state == "alive"
    assert Game.get_hero!(hero.id).gold == hero.gold - price
  end

  test "preview death panel explains insufficient gold without offering an unavailable buyback", %{conn: conn} do
    hero = create_base_hero(%{pve_state: "dead", gold: 0, level: 10, pve_tier: 1})
    conn = conn |> log_in_user(hero.player.user) |> put_session(:player_id, hero.player_id)
    {:ok, view, _} = live(conn, "/training")

    assert has_element?(view, "#buyback-hero[disabled][aria-describedby=death-gold-help]")
    assert has_element?(view, "#death-gold-help", "Sell an item in the Shop")
    assert has_element?(view, "#restart-hero")
    assert has_element?(view, "#death-new-hero")
    refute has_element?(view, "#shard-buyback-hero")
  end

  test "preview death panel offers an eligible shard buyback with its balance", %{conn: conn} do
    user = create_user(%{shard_count: 100})
    hero = create_base_hero(%{pve_state: "dead", gold: 0, pve_tier: 4}, create_player!(%{}, user))
    price = Moba.shard_buyback_price(user.shard_count)
    conn = conn |> log_in_user(user) |> put_session(:player_id, hero.player_id)
    {:ok, view, _} = live(conn, "/training")

    assert has_element?(view, "#death-shard-cost", "#{price}")
    assert has_element?(view, ".death-buybacks", "100 Shards available")
    view |> element("#shard-buyback-hero") |> render_click()

    refute has_element?(view, "#death-panel")
    assert Game.get_hero!(hero.id).pve_state == "alive"
    assert Accounts.get_user!(user.id).shard_count == user.shard_count - price
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

  test "preview Roshan intro shows health, attempts and starts the boss battle", %{conn: conn} do
    hero =
      create_base_hero(%{
        league_tier: Moba.master_league_tier(),
        pve_current_turns: 0,
        pve_total_turns: 0
      })
      |> Game.generate_boss!()

    boss = Game.get_hero!(hero.boss_id)
    conn = init_test_session(conn, player_id: hero.player_id)
    {:ok, first_attempt, _} = live(conn, "/training")

    assert has_element?(first_attempt, "#roshan-challenge[data-attempt='1']")
    assert has_element?(first_attempt, "#roshan-title", "Roshan")
    assert has_element?(first_attempt, ".roshan-abilities img")
    assert has_element?(first_attempt, "#roshan-health[aria-valuenow='#{boss.total_hp}']")
    refute has_element?(first_attempt, "#roshan-recovery")

    GenServer.stop(first_attempt.pid)
    remaining_hp = div(boss.total_hp, 2)
    Game.update_hero!(boss, %{league_attempts: 1, total_hp: remaining_hp})
    {:ok, second_attempt, _} = live(conn, "/training")

    assert has_element?(second_attempt, "#roshan-challenge[data-attempt='2']")
    assert has_element?(second_attempt, "#roshan-health[aria-valuenow='#{remaining_hp}']")
    assert has_element?(second_attempt, "#roshan-recovery", "final attempt")

    {:ok, battle_view, _} =
      second_attempt
      |> element("#start-league-challenge")
      |> render_click()
      |> follow_redirect(conn)

    battle = Engine.latest_battle(hero.id)
    assert has_element?(battle_view, "#battle-page")
    assert battle.type == "league"
    assert battle.defender_id == boss.id
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
    assert html =~ "Roshan"
    assert has_element?(view, "#roshan-recovery", "final attempt")
    assert has_element?(view, "#start-league-challenge")

    {:ok, _battle_view, battle_html} =
      view
      |> element("#start-league-challenge")
      |> render_click()
      |> follow_redirect(conn)

    assert battle_html =~ "Make your first move"

    battle = Engine.latest_battle(hero.id)
    detailed_battle = Engine.get_battle!(battle.id)
    assert battle.type == "league"
    assert detailed_battle.defender.bot_difficulty == "boss"
  end
end
