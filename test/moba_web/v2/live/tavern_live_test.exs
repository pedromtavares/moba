defmodule MobaWeb.V2.TavernLiveTest do
  use MobaWeb.ConnCase
  import Phoenix.LiveViewTest

  describe "connected mount" do
    test "renders tavern tabs and shard header", %{conn: conn} do
      hero = create_base_hero()

      conn =
        conn
        |> log_in_user(hero.player.user)
        |> put_session(:player_id, hero.player_id)

      {:ok, view, html} = live(conn, "/tavern")

      assert html =~ "Skins"
      assert has_element?(view, "#tavern-heading")
      assert has_element?(view, "#show-avatars-link[aria-selected=true] .nav-emblem")
      assert has_element?(view, "#tavern-avatars .tavern-avatar-stage h2", "Tinker")
      assert has_element?(view, "#tavern-discord-unlock")

      view |> element("#browse-avatar-bloodseeker") |> render_click()
      assert has_element?(view, "#tavern-avatars .tavern-avatar-stage h2", "Bloodseeker")
      assert has_element?(view, "#browse-avatar-bloodseeker[aria-pressed=true]")
      refute has_element?(view, "#show-skills-link, .tavern-skill-card, [phx-click=unlock-skill]")
      assert has_element?(view, "#show-skins-link .nav-emblem")
    end
  end

  describe "tab and skin interactions" do
    test "switches tabs and selects avatar on skins tab", %{conn: conn} do
      hero = create_base_hero()

      conn =
        conn
        |> log_in_user(hero.player.user)
        |> put_session(:player_id, hero.player_id)

      {:ok, view, _html} = live(conn, "/tavern")

      render_click(view, "show-skins")
      assert has_element?(view, "#show-skins-link.active")
      view |> element("#set-avatar-phantom_assassin") |> render_click()
      assert has_element?(view, "#tavern-skins #set-avatar-phantom_assassin[aria-pressed=true]")
      render_click(view, "show-avatars")
      assert has_element?(view, "#tavern-avatars")
    end
  end
end
