defmodule MobaWeb.V2.ArenaLiveTest do
  use MobaWeb.ConnCase

  import Phoenix.LiveViewTest

  test "renders arena index and edit routes under /v2", %{conn: conn} do
    hero = create_base_hero()

    conn =
      conn
      |> init_test_session(player_id: hero.player_id)

    {:ok, arena_view, arena_html} = live(conn, "/arena")
    assert arena_html =~ "Enter the Arena"
    assert arena_html =~ "Edit Teams"
    assert has_element?(arena_view, ~s|#matchmaking-container[phx-hook="EqualHeight"][phx-target=".arena .ranking"]|)
    assert has_element?(arena_view, ~s|#pvp_duels[phx-hook="EqualHeight"][phx-target=".arena .ranking"]|)

    {:ok, edit_view, _html} = live(conn, "/arena/edit")
    assert has_element?(edit_view, "#arena-team-form")
    assert has_element?(edit_view, ~s|#current-team-container[phx-hook="EqualHeight"][phx-target="#teams-container"]|)
    assert has_element?(edit_view, ~s|#heroes-container[phx-hook="EqualHeight"][phx-target="#teams-container"]|)
  end

  test "creates a team from the v2 edit screen", %{conn: conn} do
    hero = create_base_hero()

    conn =
      conn
      |> init_test_session(player_id: hero.player_id)

    {:ok, view, _html} = live(conn, "/arena/edit")

    html =
      view
      |> form("#arena-team-form", %{"team" => %{"name" => "Five Stack"}})
      |> render_submit()

    assert html =~ "Five Stack"
  end

  test "renders team row avatars inline on arena edit", %{conn: conn} do
    hero = create_base_hero()

    extra_heroes =
      for index <- 1..4 do
        Game.create_hero!(%{name: "Extra #{index}"}, hero.player, strong_avatar(), base_skills())
      end

    team =
      Game.create_team!(%{
        name: "Inline",
        player_id: hero.player_id,
        pick_ids: [hero.id | Enum.map(extra_heroes, & &1.id)]
      })

    conn =
      conn
      |> init_test_session(player_id: hero.player_id)

    {:ok, view, _html} = live(conn, "/arena/edit")
    team_row_html = view |> element("#team-row-#{team.id}") |> render()

    assert length(Regex.scan(~r/class="avatar-container"/, team_row_html)) == 5
  end

  test "edits a team hero inline from the arena screen", %{conn: conn} do
    hero = create_base_hero()
    team = Game.create_team!(%{name: "Inline", player_id: hero.player_id, pick_ids: [hero.id]})

    conn =
      conn
      |> init_test_session(player_id: hero.player_id)

    {:ok, view, _html} = live(conn, "/arena/edit")

    render_click(view, "select-team", %{"id" => "#{team.id}"})
    refute has_element?(view, "#hero-bar")

    render_click(view, "edit-hero", %{"id" => "#{hero.id}"})

    assert has_element?(view, "#hero-bar")
    assert has_element?(view, "#edit-button")
    assert has_element?(view, ".xp-bar")
    assert has_element?(view, "#toggle-shop")

    view
    |> element("#hero-bar #edit-button")
    |> render_click()

    assert has_element?(view, "#hero-bar #save-button")
    assert has_element?(view, "#hero-bar select[name='skill_order[decay]']")
  end
end
