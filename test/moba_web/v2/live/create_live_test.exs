defmodule MobaWeb.V2.CreateLiveTest do
  use MobaWeb.ConnCase
  import Phoenix.LiveViewTest

  describe "connected mount" do
    test "renders avatar selection state", %{conn: conn} do
      hero = create_base_hero()

      conn =
        conn
        |> log_in_user(hero.player.user)
        |> put_session(:player_id, hero.player_id)

      {:ok, view, html} = live(conn, "/invoke")

      assert html =~ "Pick your"
      assert has_element?(view, "#randomize-button")
    end
  end

  describe "creation flow" do
    test "pick avatar and build enables create button", %{conn: conn} do
      hero = create_base_hero()

      conn =
        conn
        |> log_in_user(hero.player.user)
        |> put_session(:player_id, hero.player_id)

      {:ok, view, _html} = live(conn, "/invoke")

      avatar = Game.list_creation_avatars(Accounts.unlocked_codes_for(hero.player.user)) |> List.first()

      html = render_click(view, "pick-avatar", %{"id" => avatar.id})
      assert html =~ "Pick a Skill Build"

      html = render_click(view, "pick-build", %{"number" => "0"})
      assert html =~ "create-button"
      assert html =~ "Invoke"
    end
  end
end
