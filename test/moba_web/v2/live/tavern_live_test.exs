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
      assert has_element?(view, "#show-avatars-link")
      assert has_element?(view, "#show-skills-link")
      assert has_element?(view, "#show-skins-link")
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

      render_click(view, "show-skills")
      assert has_element?(view, "#show-skills-link.active")

      render_click(view, "show-skins")
      html = render_click(view, "set-avatar", %{"code" => "phantom_assassin"})
      assert html =~ "Skins"
    end
  end
end
