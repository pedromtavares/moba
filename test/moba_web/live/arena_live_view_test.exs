defmodule MobaWeb.ArenaLiveViewTest do
  use MobaWeb.ConnCase
  import Phoenix.LiveViewTest

  test "connected mount", %{conn: conn} do
    hero = create_pvp_hero()

    conn = Pow.Plug.assign_current_user(conn, hero.user, otp_app: :moba)

    {:ok, _view, html} = live(conn, "/arena")
    assert html =~ "Arena"
  end

  test "connected mount redirects if there is no pve hero", %{conn: conn} do
    hero = create_base_hero()

    conn = Pow.Plug.assign_current_user(conn, hero.user, otp_app: :moba)

    live(conn, "/arena") |> follow_redirect(conn, "/jungle")
  end

  test "battle event", %{conn: conn} do
    create_pvp_hero(%{league_tier: 5})
    create_pvp_hero(%{league_tier: 5})
    create_pvp_hero(%{league_tier: 5})

    hero = create_pvp_hero(%{league_tier: 5})

    conn = Pow.Plug.assign_current_user(conn, hero.user, otp_app: :moba)

    {filter, results} = Game.pvp_search(hero)

    target = Game.get_hero!(List.first(results).id)

    {:ok, view, _html} = live(conn, "/arena")

    {:ok, _, html} =
      render_click(view, :battle, %{"id" => target.id, "number" => target.active_build_id}) |> follow_redirect(conn)

    assert html =~ "Click to select a skill"
    assert filter == "normal"
  end
end
