defmodule MobaWeb.V2.LibraryLiveTest do
  use MobaWeb.ConnCase

  import Phoenix.LiveViewTest

  test "renders the library route with the main guide tabs", %{conn: conn} do
    hero = create_base_hero()

    conn =
      conn
      |> log_in_user(hero.player.user)
      |> put_session(:player_id, hero.player_id)

    {:ok, view, html} = live(conn, "/v2/library")

    assert html =~ "Frequently Asked Questions"
    assert html =~ "Training Guide"
    assert html =~ "Arena Guide"
    assert html =~ "Contact"
    assert has_element?(view, "#library")
  end
end
