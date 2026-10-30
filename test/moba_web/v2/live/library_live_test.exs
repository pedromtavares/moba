defmodule MobaWeb.V2.LibraryLiveTest do
  use MobaWeb.ConnCase

  import Phoenix.LiveViewTest

  test "renders the library route with the main guide tabs", %{conn: conn} do
    hero = create_base_hero()

    conn =
      conn
      |> log_in_user(hero.player.user)
      |> put_session(:player_id, hero.player_id)

    {:ok, view, html} = live(conn, "/library")

    assert html =~ "Frequently Asked Questions"
    assert html =~ "Training Guide"
    assert html =~ "Arena Guide"
    refute has_element?(view, "#manual-navigation a[href='#about-tab'], #manual-navigation a[href='#support-tab']")
    refute has_element?(view, "#about-tab, #support-tab")
    assert has_element?(view, "#library")
    assert has_element?(view, "#library .skill-img[title]")
    assert has_element?(view, "#library .img-border-sm[title]")
  end
end
