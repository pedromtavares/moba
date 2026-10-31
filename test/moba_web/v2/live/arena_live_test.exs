defmodule MobaWeb.V2.ArenaLiveTest do
  use MobaWeb.ConnCase

  import Phoenix.LiveViewTest

  test "renders canonical arena and team editor routes", %{conn: conn} do
    hero = create_base_hero()

    conn =
      conn
      |> init_test_session(player_id: hero.player_id)

    {:ok, arena_view, arena_html} = live(conn, "/arena")
    assert arena_html =~ "Play 5v5"
    assert arena_html =~ "Play 1v1"
    assert has_element?(arena_view, ".arena-play-actions > #enter-arena-button:first-child", "Play 5v5")
    assert has_element?(arena_view, ".arena-play-actions > #season-duel-button:last-child", "Play 1v1")
    assert has_element?(arena_view, "#arena-header-footer dt", "5v5 Win Rate")
    assert has_element?(arena_view, "#arena-header-footer dt", "Daily 5v5 wins")
    refute has_element?(arena_view, "#edit-teams-button")
    assert has_element?(arena_view, ~s|#matchmaking-container[phx-hook="EqualHeight"][phx-target=".arena .ranking"]|)
    assert has_element?(arena_view, ~s|#pvp_duels[phx-hook="EqualHeight"][phx-target=".arena .ranking"]|)

    {:ok, edit_view, _html} = live(conn, "/arena/edit")
    assert has_element?(edit_view, "#arena-team-form")
    assert has_element?(edit_view, "#teams-return-button[href='/arena']", "Return to arena")
    assert has_element?(edit_view, "#teams-hud #current-team-container.squad-panel")
    assert has_element?(edit_view, "#teams-hud #heroes-container.squad-panel")
  end

  test "teams returns to the match that opened it even when a newer match exists", %{conn: conn} do
    hero = create_base_hero()
    opponent = create_player!()
    source = teams_return_match(hero.player, opponent)
    teams_return_match(hero.player, opponent)
    conn = init_test_session(conn, player_id: hero.player_id)

    {:ok, view, _} = live(conn, "/arena/edit?match_id=#{source.id}")
    assert has_element?(view, "#teams-return-button[href='/matches/#{source.id}']", "Return to match")
  end

  test "direct teams links return to the latest own match and ignore invalid or other players' ids", %{conn: conn} do
    hero = create_base_hero()
    opponent = create_player!()
    own = teams_return_match(hero.player, opponent)
    other = teams_return_match(opponent, hero.player)

    own
    |> Ecto.Changeset.change(inserted_at: ~N[2020-01-01 00:00:00])
    |> Moba.Repo.update!()

    conn = init_test_session(conn, player_id: hero.player_id)

    for path <- ["/arena/edit", "/arena/edit?match_id=#{other.id}", "/arena/edit?match_id=invalid"] do
      {:ok, view, _} = live(conn, path)
      assert has_element?(view, "#teams-return-button[href='/matches/#{own.id}']", "Return to match")
    end
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

  test "history switches between matches and duels while live 1v1 owns the third column", %{conn: conn} do
    player = create_player!()
    {:ok, view, _} = live(init_test_session(conn, player_id: player.id), "/arena")
    assert has_element?(view, "#arena-history-matches-tab[aria-pressed=true]")
    assert has_element?(view, "#arena-no-matches")
    assert has_element?(view, "#arena-history-matches > #arena-no-matches", "Your first 5v5 awaits")
    refute has_element?(view, "#arena-matches-table")
    refute has_element?(view, "#arena-duel-history-section")
    assert has_element?(view, "#pvp_duels #arena-live-section")
    assert has_element?(view, "#season-duel-button .ui-swords")
    assert has_element?(view, "#enter-arena-button .ui-strategy")
    assert has_element?(view, "#arena-entry-reward", "+20 Shards")

    view |> element("#arena-history-duels-tab") |> render_click()
    assert has_element?(view, "#arena-history-duels-tab[aria-pressed=true]")
    assert has_element?(view, "#matchmaking-container #arena-no-duels")
    assert has_element?(view, "#arena-no-duels", "Your first 1v1 awaits")
    refute has_element?(view, "#arena-matches-table")
    refute has_element?(view, "#pvp_duels #arena-duels-table")

    view |> element("#arena-history-matches-tab") |> render_click()
    assert has_element?(view, "#arena-no-matches")
  end

  test "the reward copy disappears after a mixture of thirty matches and duels", %{conn: conn} do
    player = create_player!()
    opponent = create_player!()

    for _ <- 1..15 do
      Game.Matches.create!(%{
        player_id: player.id,
        opponent_id: opponent.id,
        type: "manual",
        phase: "scored",
        player_picks: [],
        opponent_picks: [],
        generated_picks: [],
        rewards: %{attacker_pvp_points: 0}
      })

      duel = Game.Duels.create!(player, opponent, true)
      Game.Duels.finish!(duel, %{winner: player, attacker_pvp_points: 5, defender_pvp_points: 0})
    end

    {:ok, view, _} = live(init_test_session(conn, player_id: player.id), "/arena")
    refute has_element?(view, "#arena-entry-reward")
    assert has_element?(view, "#season-duel-button:not([disabled])", "Play 1v1")
    assert has_element?(view, "#enter-arena-button:not([disabled])", "Play 5v5")
    refute has_element?(view, "#arena-daily-limit")
  end

  test "both play buttons resume their active games even outside recent history", %{conn: conn} do
    player = create_player!()
    opponent = create_player!()
    pending = Game.Duels.create!(player, opponent, true)

    for _ <- 1..16 do
      duel = Game.Duels.create!(player, opponent, true)
      Game.Duels.finish!(duel, %{winner: player, attacker_pvp_points: 5, defender_pvp_points: 0})
    end

    match =
      Game.Matches.create!(%{
        player_id: player.id,
        opponent_id: opponent.id,
        type: "manual",
        player_picks: [],
        opponent_picks: [],
        generated_picks: []
      })

    {:ok, view, _} = live(init_test_session(conn, player_id: player.id), "/arena")
    assert has_element?(view, "#pvp-progression #resume-arena-duel[href='/arena/#{pending.id}']", "Resume 1v1")
    assert has_element?(view, "#pvp-progression #resume-arena-match[href='/matches/#{match.id}']", "Resume 5v5")
    assert has_element?(view, ".arena-play-actions > #resume-arena-match:first-child")
    assert has_element?(view, ".arena-play-actions > #resume-arena-duel:last-child")
    refute has_element?(view, "#season-duel-button, #enter-arena-button")
    render_click(view, "season-duel")
    assert_redirect(view, "/arena/#{pending.id}")
    assert length(Game.list_duels(player)) == 15
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

    for pick <- team.picks do
      assert has_element?(
               view,
               "#team-row-#{team.id} img[src='#{MobaWeb.V2.Components.GameHelpers.image_url(pick.avatar)}']"
             )
    end
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
    assert has_element?(view, ".hud-experience")
    assert has_element?(view, "#toggle-shop")

    view
    |> element("#hero-bar #edit-button")
    |> render_click()

    assert has_element?(view, "#hero-bar #save-button")
    assert has_element?(view, "#hero-bar select[name='skill_order[decay]']")

    view
    |> element("#hero-bar #toggle-shop")
    |> render_click()

    assert has_element?(view, "#shop-modal.d-block")
  end

  test "skips the retired arena tutorial when the player is on step 29", %{conn: conn} do
    hero = create_base_hero()
    player = Game.update_tutorial_step!(hero.player, 29)

    conn =
      conn
      |> init_test_session(player_id: player.id)

    {:ok, view, _html} = live(conn, "/arena")

    refute has_element?(view, "[phx-hook=TutorialStep]")
    assert Game.get_player!(player.id).tutorial_step == 39
  end

  test "arena tutorial keeps the v1 anchor targets", %{conn: conn} do
    hero = create_base_hero()

    player =
      hero.player
      |> Game.update_collection!([%{id: hero.id}])
      |> Game.update_tutorial_step!(29)

    conn =
      conn
      |> init_test_session(player_id: player.id)

    {:ok, view, _html} = live(conn, "/arena")

    assert has_element?(view, "#pvp-progression")
    assert has_element?(view, "#daily-progression")
    assert has_element?(view, "#current-pvp-tier")
    assert has_element?(view, "#game-manual")
  end

  defp teams_return_match(player, opponent) do
    Game.Matches.create!(%{
      player_id: player.id,
      opponent_id: opponent.id,
      type: "manual",
      player_picks: [],
      opponent_picks: [],
      generated_picks: []
    })
  end
end
