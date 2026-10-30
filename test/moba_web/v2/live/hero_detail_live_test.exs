defmodule MobaWeb.V2.HeroDetailLiveTest do
  use MobaWeb.ConnCase
  import Phoenix.LiveViewTest

  test "owner detail keeps the loadout, plain stats and skin navigation", %{conn: conn} do
    hero = create_base_hero() |> Game.buy_item!(base_item())
    conn = conn |> log_in_user(hero.player.user) |> put_session(:player_id, hero.player_id)
    {:ok, view, _} = live(conn, "/hero/#{hero.id}")

    assert has_element?(view, "#hero-detail-name", hero.name)
    assert has_element?(view, "#hero-detail-loadout #skill-#{hd(hero.skills).id}-#{hero.id}")
    assert has_element?(view, "#hero-detail-loadout #item-#{hd(hero.items).id}-#{hero.id}")
    assert has_element?(view, "#hero-detail-stats .hero-stats")
    refute has_element?(view, "#hero-detail-stats button")
    assert has_element?(view, "#hero-view-skins[href^='/tavern?']")
    assert has_element?(view, "#hero-detail-player[href='/player/#{hero.player_id}']")
    assert has_element?(view, "#hero-training-status[data-finished='false']")
    assert has_element?(view, "#hero-detail-duration", "#{hero.pve_current_turns + hero.pve_total_turns}")
  end

  test "owners open customization on demand and closing resets the HUD", %{conn: conn} do
    hero = create_base_hero()
    conn = init_test_session(conn, player_id: hero.player_id)
    {:ok, view, _} = live(conn, "/hero/#{hero.id}")

    refute has_element?(view, "#hero-bar")
    refute has_element?(view, "#hero-review.content-with-hero-bar")
    assert has_element?(view, "#customize-hero[aria-expanded=false]", "Customize hero")
    view |> element("#customize-hero") |> render_click()
    assert has_element?(view, "#customize-hero[aria-expanded=true]", "Close customization")
    assert has_element?(view, "#hero-review.content-with-hero-bar")
    assert has_element?(view, "#hero-bar #edit-button")
    view |> element("#edit-button") |> render_click()
    view |> element("#toggle-shop") |> render_click()
    assert has_element?(view, "#shop-modal.d-block")

    view |> element("#customize-hero") |> render_click()
    refute has_element?(view, "#hero-bar")
    refute has_element?(view, "#shop-modal")
    view |> element("#customize-hero") |> render_click()
    assert has_element?(view, "#hero-bar #edit-button")
    refute has_element?(view, "#hero-bar #save-button")
    assert has_element?(view, "#shop-modal.d-none")

    other = create_base_hero()
    render_patch(view, "/hero/#{other.id}")
    refute has_element?(view, "#customize-hero")
    refute has_element?(view, "#hero-bar")
  end

  test "guest owners can open their hero HUD", %{conn: conn} do
    hero = create_base_hero(%{}, Game.create_player!(%{user_id: nil}))
    {:ok, view, _} = live(init_test_session(conn, player_id: hero.player_id), "/hero/#{hero.id}")
    refute has_element?(view, "#hero-detail-player")
    refute has_element?(view, "#hero-bar")
    view |> element("#customize-hero") |> render_click()
    assert has_element?(view, "#hero-bar")
  end

  test "another player's hero has a profile link without owner controls", %{conn: conn} do
    hero = create_base_hero()
    viewer = create_base_hero()
    conn = conn |> log_in_user(viewer.player.user) |> put_session(:player_id, viewer.player_id)
    {:ok, view, _} = live(conn, "/hero/#{hero.id}")

    assert has_element?(view, "#hero-detail-player[href='/player/#{hero.player_id}']")
    refute has_element?(view, "#hero-detail-skins")
    refute has_element?(view, "#customize-hero")
    render_click(view, "toggle-customize")
    refute has_element?(view, "#hero-bar")
  end

  test "finished unranked hero remains visible below the leaderboard with capped time", %{conn: conn} do
    hero = create_base_hero(%{finished_at: Timex.now()})
    inserted_at = hero.finished_at |> DateTime.add(-7200) |> DateTime.to_naive()
    hero = hero |> Ecto.Changeset.change(inserted_at: inserted_at) |> Moba.Repo.update!()
    conn = conn |> log_in_user(hero.player.user) |> put_session(:player_id, hero.player_id)
    {:ok, view, _} = live(conn, "/hero/#{hero.id}")

    assert has_element?(view, "#hero-training-status[data-finished='true']")
    assert has_element?(view, "#hero-detail-duration", "99+")
    assert has_element?(view, "#ranking-#{hero.id} [aria-label='Unranked']")
    assert has_element?(view, "#hero-leaderboard tfoot #ranking-#{hero.id}[data-current='true']")
    assert has_element?(view, "#ranking-#{hero.id} a[aria-current='page']")
    assert has_element?(view, "#hero-league-title", Moba.leagues()[hero.league_tier])
  end

  test "a ranked hero is highlighted in the leaderboard without a duplicate footer", %{conn: conn} do
    hero = create_base_hero(%{finished_at: Timex.now(), pve_ranking: 1})
    Cachex.put(:game_cache, "pve_ranking", [hero])
    on_exit(fn -> Cachex.del(:game_cache, "pve_ranking") end)
    conn = conn |> log_in_user(hero.player.user) |> put_session(:player_id, hero.player_id)
    {:ok, view, _} = live(conn, "/hero/#{hero.id}")

    assert has_element?(view, "#ranking-#{hero.id} .hero-ranking-position", "#1")
    assert has_element?(view, "#hero-leaderboard tbody #ranking-#{hero.id}[data-current='true']")
    refute has_element?(view, "#hero-leaderboard tfoot")
  end
end
