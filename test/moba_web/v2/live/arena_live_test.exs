defmodule MobaWeb.V2.ArenaLiveTest do
  use MobaWeb.ConnCase

  import Phoenix.LiveViewTest

  test "renders canonical arena and team editor routes", %{conn: conn} do
    hero = create_base_hero()

    conn =
      conn
      |> log_in_player(player_id: hero.player_id)

    {:ok, arena_view, arena_html} = live(conn, "/arena")
    assert arena_html =~ "Play 3v3"
    assert arena_html =~ "Play 1v1"

    assert has_element?(
             arena_view,
             ".arena-play-actions > .arena-play-3v3:first-child > #enter-arena-button[data-game-fullscreen]",
             "Play 3v3"
           )

    assert has_element?(
             arena_view,
             ".arena-play-actions > .arena-play-1v1:last-child > #season-duel-button[data-game-fullscreen]",
             "Play 1v1"
           )

    assert has_element?(arena_view, "#arena-header-footer dt", "3v3 Win Rate")
    assert has_element?(arena_view, "#arena-header-footer dt", "Daily 3v3 wins")
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
    conn = log_in_player(conn, player_id: hero.player_id)

    {:ok, view, _} = live(conn, "/arena/edit?match_id=#{source.id}")
    assert has_element?(view, "#teams-return-button[href='/matches/#{source.id}']", "Return to match")
  end

  test "the team editor defaults to farm and uses fastest training time to break ties", %{conn: conn} do
    player = create_player!()
    start = DateTime.utc_now() |> DateTime.add(-600) |> DateTime.truncate(:second)

    [slow, fast, recent] =
      for {gold, xp, seconds, rank} <- [{30_000, 30_000, 300, 1}, {25_000, 35_000, 120, nil}, {20_000, 30_000, 540, 2}] do
        create_combat_hero(
          %{
            league_tier: Moba.master_league_tier(),
            finished_at: DateTime.add(start, seconds),
            total_gold_farm: gold,
            total_xp_farm: xp,
            pve_ranking: rank
          },
          player
        )
        |> Ecto.Changeset.change(inserted_at: DateTime.to_naive(start))
        |> Moba.Repo.update!()
      end

    {:ok, view, _} = live(log_in_player(conn, player_id: player.id), "/arena/edit")

    for {label, first, second} <- [
          {"Farm", fast, slow},
          {"Recent", recent, slow},
          {"Rank", slow, recent},
          {"Farm", fast, slow}
        ] do
      assert has_element?(view, "#hero-sort", label)

      assert has_element?(
               view,
               ".workshop-collection-grid > #available-hero-#{first.id}:first-child + #available-hero-#{second.id}"
             )

      view |> element("#hero-sort") |> render_click()
    end
  end

  test "the arena and profile show the same recent 3v3 rate", %{conn: conn} do
    player = create_player!(%{total_matches: 20, total_wins: 19})
    opponent = create_player!()

    for winner_id <- [player.id, opponent.id] do
      Game.Matches.create!(%{
        player_id: player.id,
        opponent_id: opponent.id,
        winner_id: winner_id,
        phase: "scored",
        type: "manual",
        rewards: %{attacker_pvp_points: 0}
      })
    end

    conn = log_in_player(conn, player_id: player.id)
    {:ok, arena, _} = live(conn, "/arena")
    assert has_element?(arena, "#arena-header-footer dd.arena-stat-blue", "50%")
    assert has_element?(arena, "#arena-matches-pager #arena-matches-table tbody[data-listing-rows]")
    assert has_element?(arena, "#arena-matches-pager-controls button[aria-controls=arena-matches-pager-viewport]")

    {:ok, profile, _} = live(conn, "/player/#{player.id}")
    assert has_element?(profile, "#profile-3v3-win-rate", "50%")
  end

  test "a retained match keeps its summary when its battle replay expires", %{conn: conn} do
    player = create_player!()
    opponent = create_player!()

    match =
      Game.Matches.create!(%{
        player_id: player.id,
        opponent_id: opponent.id,
        winner_id: player.id,
        phase: "scored",
        type: "manual",
        interactive: true
      })

    conn = log_in_player(conn, player_id: player.id)
    path = "/matches/#{match.id}"
    {:ok, summary, _} = live(conn, path)
    assert has_element?(summary, "#match-battles", "Battle replays are no longer available.")
    refute has_element?(summary, "#arena-match-details")
    assert {:error, {:live_redirect, %{to: ^path}}} = live(conn, "#{path}/battles")
  end

  test "direct teams links return to the latest own match and ignore invalid or other players' ids", %{conn: conn} do
    hero = create_base_hero()
    opponent = create_player!()
    own = teams_return_match(hero.player, opponent)
    other = teams_return_match(opponent, hero.player)

    own
    |> Ecto.Changeset.change(inserted_at: ~N[2020-01-01 00:00:00])
    |> Moba.Repo.update!()

    conn = log_in_player(conn, player_id: hero.player_id)

    for path <- ["/arena/edit", "/arena/edit?match_id=#{other.id}", "/arena/edit?match_id=invalid"] do
      {:ok, view, _} = live(conn, path)
      assert has_element?(view, "#teams-return-button[href='/matches/#{own.id}']", "Return to match")
    end
  end

  test "creates a team from the v2 edit screen", %{conn: conn} do
    hero = create_base_hero()

    conn =
      conn
      |> log_in_player(player_id: hero.player_id)

    {:ok, view, _html} = live(conn, "/arena/edit")

    html =
      view
      |> form("#arena-team-form", %{"team" => %{"name" => "Five Stack"}})
      |> render_submit()

    assert html =~ "Five Stack"
  end

  test "history switches between matches and duels while live 1v1 owns the third column", %{conn: conn} do
    player = create_player!()
    {:ok, view, _} = live(log_in_player(conn, player_id: player.id), "/arena")
    assert has_element?(view, "#arena-history-matches-tab[aria-pressed=true]")
    assert has_element?(view, "#arena-no-matches")
    assert has_element?(view, "#arena-history-matches > #arena-no-matches", "Your first 3v3 awaits")
    refute has_element?(view, "#arena-matches-table")
    refute has_element?(view, "#arena-duel-history-section")
    assert has_element?(view, "#pvp_duels #arena-live-section")
    assert has_element?(view, "#season-duel-button .ui-swords")
    assert has_element?(view, "#enter-arena-button .ui-arena-3v3")
    assert has_element?(view, "#arena-entry-reward", "+30 Shards")
    assert has_element?(view, "#daily-progression[aria-valuemax='20']")

    view |> element("#arena-history-duels-tab") |> render_click()
    assert has_element?(view, "#arena-history-duels-tab[aria-pressed=true]")
    assert has_element?(view, "#matchmaking-container #arena-no-duels")
    assert has_element?(view, "#arena-no-duels", "Your first 1v1 awaits")
    refute has_element?(view, "#arena-matches-table")
    refute has_element?(view, "#pvp_duels #arena-duels-table")

    view |> element("#arena-history-matches-tab") |> render_click()
    assert has_element?(view, "#arena-no-matches")
  end

  test "the reward copy disappears after a mixture of twenty matches and duels", %{conn: conn} do
    player = create_player!()
    opponent = create_player!()

    for _ <- 1..10 do
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

    {:ok, view, _} = live(log_in_player(conn, player_id: player.id), "/arena")
    refute has_element?(view, "#arena-entry-reward")
    assert has_element?(view, "#season-duel-button:not([disabled])", "Play 1v1")
    assert has_element?(view, "#enter-arena-button:not([disabled])", "Play 3v3")
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

    {:ok, view, _} = live(log_in_player(conn, player_id: player.id), "/arena")
    assert has_element?(view, "#pvp-progression #resume-arena-duel[href='/arena/#{pending.id}']", "Resume 1v1")
    assert has_element?(view, "#pvp-progression #resume-arena-match[href='/matches/#{match.id}']", "Resume 3v3")
    assert has_element?(view, ".arena-play-actions > .arena-play-3v3:first-child > #resume-arena-match")
    assert has_element?(view, ".arena-play-actions > .arena-play-1v1:last-child > #resume-arena-duel")
    refute has_element?(view, "#season-duel-button, #enter-arena-button")
    render_click(view, "season-duel")
    assert_redirect(view, "/arena/#{pending.id}")
    assert length(Game.list_duels(player)) == 15
  end

  test "renders team row avatars inline on arena edit", %{conn: conn} do
    hero = create_base_hero()

    extra_heroes =
      for index <- 1..2 do
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
      |> log_in_player(player_id: hero.player_id)

    {:ok, view, _html} = live(conn, "/arena/edit")

    for pick <- team.picks do
      assert has_element?(
               view,
               "#team-row-#{team.id} img[src='#{MobaWeb.V2.Components.GameHelpers.image_url(pick.avatar)}']"
             )
    end
  end

  test "edits a team hero inline from the arena screen", %{conn: conn} do
    item = base_item()
    hero = create_base_hero(%{gold: 10_000}) |> Game.buy_item!(item)
    team = Game.create_team!(%{name: "Inline", player_id: hero.player_id, pick_ids: [hero.id]})

    conn =
      conn
      |> log_in_player(player_id: hero.player_id)

    {:ok, view, _html} = live(conn, "/arena/edit")

    render_click(view, "select-team", %{"id" => "#{team.id}"})
    refute has_element?(view, "#hero-bar")

    render_click(view, "edit-hero", %{"id" => "#{hero.id}"})

    assert has_element?(view, "#hero-bar")
    assert has_element?(view, "#edit-button")
    assert has_element?(view, ".hud-experience")
    assert has_element?(view, "#toggle-shop")

    view |> element("#inventory-#{item.id}") |> render_click()
    assert has_element?(view, "#shop-modal.d-block")
    assert has_element?(view, "#shop-detail-name", item.name)
    assert has_element?(view, "#sell-#{item.id}")
    view |> element("#close-button") |> render_click()

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

  test "ignores retired tutorial state when entering Arena", %{conn: conn} do
    hero = create_base_hero()
    player = Game.update_tutorial_step!(hero.player, 29)

    conn =
      conn
      |> log_in_player(player_id: player.id)

    {:ok, view, _html} = live(conn, "/arena")

    refute has_element?(view, "[phx-hook=TutorialStep]")
    assert Game.get_player!(player.id).tutorial_step == 29
  end

  test "arena tutorial keeps the v1 anchor targets", %{conn: conn} do
    hero = create_base_hero()

    player =
      hero.player
      |> Game.update_collection!([%{id: hero.id}])
      |> Game.update_tutorial_step!(29)

    conn =
      conn
      |> log_in_player(player_id: player.id)

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
