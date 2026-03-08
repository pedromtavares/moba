defmodule MobaWeb.V2.CommunityLiveTest do
  use MobaWeb.ConnCase

  import Phoenix.LiveViewTest

  test "renders community and switches ranking tabs", %{conn: conn} do
    hero = create_base_hero()

    conn =
      conn
      |> log_in_user(hero.player.user)
      |> put_session(:player_id, hero.player_id)

    {:ok, view, html} = live(conn, "/community")

    assert html =~ "Message Board"
    assert html =~ "Updates"
    assert has_element?(view, "#community-message-form")
    assert has_element?(view, "#show-online-link")

    render_click(view, "show-pvp", %{})
    assert has_element?(view, "#show-pvp-link.active")

    render_click(view, "show-pve", %{})
    assert has_element?(view, "#show-pve-link.active")
  end

  test "creates a community message", %{conn: conn} do
    hero = create_base_hero()

    conn =
      conn
      |> log_in_user(hero.player.user)
      |> put_session(:player_id, hero.player_id)

    {:ok, view, _html} = live(conn, "/community")

    html =
      view
      |> form("#community-message-form", %{"message" => %{"body" => "Parity audit message"}})
      |> render_submit()

    assert html =~ "Message Board"

    [message | _] = Accounts.latest_messages("community", "general", 1)
    assert message.body == "Parity audit message"
  end
end
