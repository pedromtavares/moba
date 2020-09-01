defmodule MobaWeb.JungleLiveViewTest do
  use MobaWeb.ConnCase
  import Phoenix.LiveViewTest

  test "connected mount", %{conn: conn} do
    hero = create_base_hero()

    conn = Pow.Plug.assign_current_user(conn, hero.user, otp_app: :moba)

    {:ok, _view, html} = live(conn, "/jungle")
    assert html =~ "Jungle"
  end

  test "connected mount redirects if there is no pve hero", %{conn: conn} do
    hero = create_pvp_hero()

    user = Accounts.get_user!(hero.user_id) |> Accounts.update_user!(%{current_pve_hero_id: nil})

    conn = Pow.Plug.assign_current_user(conn, user, otp_app: :moba)

    live(conn, "/jungle") |> follow_redirect(conn, "/join")
  end

  test "battle event", %{conn: conn} do
    hero = create_base_hero()

    conn = Pow.Plug.assign_current_user(conn, hero.user, otp_app: :moba)

    target = Game.list_targets(hero.id) |> List.first()

    {:ok, view, _html} = live(conn, "/jungle")

    {:ok, _, html} = render_click(view, :battle, %{"id" => target.id}) |> follow_redirect(conn)

    assert html =~ "Click to select a skill"
  end
end
