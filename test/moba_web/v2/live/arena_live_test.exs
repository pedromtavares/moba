defmodule MobaWeb.V2.ArenaLiveTest do
  use MobaWeb.ConnCase

  import Phoenix.LiveViewTest

  test "renders arena index and edit routes under /v2", %{conn: conn} do
    hero = create_base_hero()

    conn =
      conn
      |> init_test_session(player_id: hero.player_id)

    {:ok, _view, arena_html} = live(conn, "/v2/arena")
    assert arena_html =~ "Enter the Arena"
    assert arena_html =~ "Edit Teams"

    {:ok, edit_view, _html} = live(conn, "/v2/arena/edit")
    assert has_element?(edit_view, "#arena-team-form")
  end

  test "creates a team from the v2 edit screen", %{conn: conn} do
    hero = create_base_hero()

    conn =
      conn
      |> init_test_session(player_id: hero.player_id)

    {:ok, view, _html} = live(conn, "/v2/arena/edit")

    html =
      view
      |> form("#arena-team-form", %{"team" => %{"name" => "Five Stack"}})
      |> render_submit()

    assert html =~ "Five Stack"
  end

  test "edits a team hero inline from the arena screen", %{conn: conn} do
    hero = create_base_hero()
    team = Game.create_team!(%{name: "Inline", player_id: hero.player_id, pick_ids: [hero.id]})

    conn =
      conn
      |> init_test_session(player_id: hero.player_id)

    {:ok, view, _html} = live(conn, "/v2/arena/edit")

    render_click(view, "select-team", %{"id" => "#{team.id}"})
    refute has_element?(view, "#hero-bar")

    render_click(view, "edit-hero", %{"id" => "#{hero.id}"})

    assert has_element?(view, "#hero-bar")
    assert has_element?(view, "#edit-button")

    render_click(view, "start-edit", %{})

    assert has_element?(view, "#save-button")
    assert has_element?(view, "select[name='skill_order[decay]']")
  end
end
