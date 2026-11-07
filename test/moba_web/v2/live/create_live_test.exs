defmodule MobaWeb.V2.CreateLiveTest do
  use MobaWeb.ConnCase
  import Phoenix.LiveViewTest

  describe "connected mount" do
    test "guest /start places the sign-in link inside the hero stage", %{conn: conn} do
      conn = get(conn, "/start")
      html = html_response(conn, 200)

      link =
        html
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#invoke-modern a#invoke-guest-sign-in[href='/users/log_in']")

      assert LazyHTML.text(link) =~ "Already registered? Sign in"
    end

    test "renders avatar selection state", %{conn: conn} do
      hero = create_base_hero()

      conn =
        conn
        |> log_in_user(hero.player.user)
        |> put_session(:player_id, hero.player_id)

      {:ok, view, _html} = live(conn, "/new")

      assert has_element?(view, "#invoke-modern #invoke-avatars")
      assert has_element?(view, "#randomize-button")
      refute has_element?(view, "#invoke-guest-sign-in")
    end
  end

  describe "creation flow" do
    test "pick avatar and build enables create button", %{conn: conn} do
      hero = create_base_hero()

      conn =
        conn
        |> log_in_user(hero.player.user)
        |> put_session(:player_id, hero.player_id)

      {:ok, view, _html} = live(conn, "/new")

      avatar = Game.list_creation_avatars(Accounts.unlocked_codes_for(hero.player.user)) |> List.first()

      render_click(view, "pick-avatar", %{"id" => avatar.id})
      assert has_element?(view, "#invoke-builds")
      assert has_element?(view, "#custom-build-button")

      html = render_click(view, "pick-build", %{"number" => "0"})
      assert html =~ "create-button"
      assert html =~ "Invoke"
      assert has_element?(view, "#create-button")
    end

    test "pick avatar and toggle custom build keeps custom controls", %{conn: conn} do
      hero = create_base_hero()

      conn =
        conn
        |> log_in_user(hero.player.user)
        |> put_session(:player_id, hero.player_id)

      {:ok, view, _html} = live(conn, "/new")

      avatar = Game.list_creation_avatars(Accounts.unlocked_codes_for(hero.player.user)) |> List.first()

      render_click(view, "pick-avatar", %{"id" => avatar.id})
      render_click(view, "toggle-custom", %{})

      assert has_element?(view, "#back-to-builds-button")
    end
  end
end
