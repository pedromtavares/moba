defmodule MobaWeb.TrainingLiveTest do
  use MobaWeb.ConnCase
  import Phoenix.LiveViewTest

  test "connected mount", %{conn: conn} do
    hero = create_base_hero()

    conn = init_test_session(conn, player_id: hero.player_id)

    {:ok, _view, html} = live(conn, "/v1/training")
    assert html =~ "MEDITATE"
  end

  test "connected mount redirects if there is no pve hero", %{conn: conn} do
    player = create_player!(%{current_pve_hero_id: nil})

    conn = init_test_session(conn, player_id: player.id)

    live(conn, "/v1/training") |> follow_redirect(conn, "/v1/base")
  end

  test "battle event", %{conn: conn} do
    hero = create_base_hero()

    conn = init_test_session(conn, player_id: hero.player_id)

    target = Game.list_targets(hero) |> List.first()

    {:ok, view, _html} = live(conn, "/v1/training")

    {:ok, _, html} = render_click(view, :battle, %{"id" => target.id}) |> follow_redirect(conn)

    assert html =~ "Click to select a skill"
  end
end
