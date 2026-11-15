defmodule MobaWeb.V2.HeroLiveTest do
  use MobaWeb.ConnCase
  import Phoenix.LiveViewTest

  describe "connected mount" do
    test "renders hero page content", %{conn: conn} do
      hero = create_base_hero()

      conn =
        conn
        |> log_in_user(hero.player.user)
        |> put_session(:player_id, hero.player_id)

      {:ok, view, html} = live(conn, "/hero/#{hero.id}")

      assert html =~ hero.name
      assert has_element?(view, "#hero-review")
      assert has_element?(view, "#ranking-card")
      assert has_element?(view, "a[href='/player/#{hero.player_id}']")
      assert has_element?(view, ".hero-stats .text-danger[title='Health']")
      assert has_element?(view, ".hero-stats .text-orange[title='Speed']")
      assert has_element?(view, "#skill-#{hero.skills |> List.first() |> Map.fetch!(:id)}-#{hero.id}")
      assert has_element?(view, ".items-container")
    end

    test "owner sees the customization action with the hero bar closed", %{conn: conn} do
      hero = create_base_hero()

      conn =
        conn
        |> log_in_user(hero.player.user)
        |> put_session(:player_id, hero.player_id)

      {:ok, view, _html} = live(conn, "/hero/#{hero.id}")

      assert has_element?(view, "#customize-hero[aria-expanded=false]")
      refute has_element?(view, "#hero-bar")
      refute has_element?(view, "#toggle-shop")
    end

    test "non-owner does not see editable hero bar", %{conn: conn} do
      hero = create_base_hero()
      viewer = create_base_hero()
      Game.update_preferences!(viewer.player, %{featured_hero_id: viewer.id})

      conn =
        conn
        |> log_in_user(viewer.player.user)
        |> put_session(:player_id, viewer.player_id)

      {:ok, view, _html} = live(conn, "/hero/#{hero.id}")

      refute has_element?(view, "#hero-bar")
      refute has_element?(view, "#toggle-shop")
      refute has_element?(view, "#set-featured-hero")

      render_click(view, "set-featured-hero")
      assert Game.get_player!(viewer.player_id).preferences.featured_hero_id == viewer.id
      refute Map.get(Game.get_player!(hero.player_id).preferences || %{}, :featured_hero_id)
    end
  end

  test "the owner's featured choice appears on fresh profiles and falls back if archived", %{conn: conn} do
    player = create_player!()
    finished_at = DateTime.utc_now() |> DateTime.truncate(:second)

    best =
      create_combat_hero(
        %{finished_at: finished_at, league_tier: Moba.max_league_tier(), total_gold_farm: Moba.max_total_farm()},
        player
      )

    choice = create_combat_hero(%{finished_at: finished_at}, player, best.avatar)
    Game.update_hero_collection!(best)

    owner_conn = log_in_player(conn, player_id: player.id)
    {:ok, hero_view, _} = live(owner_conn, "/hero/#{choice.id}")
    hero_view |> element("#hero-detail-loadout #set-featured-hero", "Set as Featured") |> render_click()
    assert has_element?(hero_view, "#set-featured-hero[disabled]", "Featured on profile")

    viewer = create_player!()
    viewer_conn = log_in_player(conn, player_id: viewer.id)
    path = "/player/#{player.id}"
    {:ok, profile, _} = live(viewer_conn, path)
    assert has_element?(profile, "#profile-featured-link[href='/hero/#{choice.id}']")

    profile |> element("#set-featured-#{best.id}") |> render_click()
    assert has_element?(profile, "#profile-featured-link[href='/hero/#{best.id}']")
    {:ok, reloaded, _} = live(viewer_conn, path)
    assert has_element?(reloaded, "#profile-featured-link[href='/hero/#{choice.id}']")

    Game.archive_hero!(choice)
    {:ok, fallback, _} = live(viewer_conn, path)
    assert has_element?(fallback, "#profile-featured-link[href='/hero/#{best.id}']")
  end

  describe "set-skin event" do
    test "updates skin selection without crashing", %{conn: conn} do
      hero = create_base_hero()
      default_skin = Game.default_skin(hero.avatar.code)

      conn =
        conn
        |> log_in_user(hero.player.user)
        |> put_session(:player_id, hero.player_id)

      {:ok, view, _html} = live(conn, "/hero/#{hero.id}")

      html = render_click(view, "set-skin", %{"skin-code" => default_skin.code})
      assert html =~ hero.name
    end
  end

  test "owner can switch hero bar into edit mode and toggle the shop", %{conn: conn} do
    hero = create_base_hero()

    conn =
      conn
      |> log_in_user(hero.player.user)
      |> put_session(:player_id, hero.player_id)

    {:ok, view, _html} = live(conn, "/hero/#{hero.id}")
    view |> element("#customize-hero") |> render_click()

    view
    |> element("#hero-bar #edit-button")
    |> render_click()

    assert has_element?(view, "#hero-bar #save-button")

    view
    |> element("#hero-bar #toggle-shop")
    |> render_click()

    assert has_element?(view, "#shop-modal.d-block")
  end
end
