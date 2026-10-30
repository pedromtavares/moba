defmodule MobaWeb.V2.HudStatesLiveTest do
  use MobaWeb.ConnCase
  import Phoenix.LiveViewTest

  test "pending duel has a full-width resume action and keeps completed history visible", %{conn: conn} do
    hero = create_base_hero()
    opponent = create_player!()
    completed = Game.create_duel!(hero.player, opponent, false)
    Game.Duels.finish!(completed, %{winner: hero.player, attacker_pvp_points: 5, defender_pvp_points: -5})
    pending = Game.create_duel!(hero.player, opponent, false)
    conn = init_test_session(conn, player_id: hero.player_id)
    {:ok, view, _} = live(conn, "/arena")

    assert has_element?(view, "#arena-pending-duel[data-tone=active]")
    assert has_element?(view, "#resume-arena-duel[href='/arena/#{pending.id}']")
    refute has_element?(view, "#pvp_duels a.col-xl-4")
    assert has_element?(view, "#arena-duels-table a[href='/arena/#{completed.id}']")
    refute has_element?(view, "#arena-duels-table a[href='/arena/#{pending.id}']")
  end

  test "a pending match stays resumable at the daily limit, then shows the reset state", %{conn: conn} do
    hero = create_base_hero()
    player = Game.update_player!(hero.player, %{daily_matches: Moba.daily_match_limit()})
    opponent = create_player!()

    for _ <- 1..(Moba.daily_match_limit() - 1) do
      create_match(player, opponent, %{phase: "scored", winner_id: player.id, rewards: %{attacker_pvp_points: 0}})
    end

    pending = create_match(player, opponent)
    conn = init_test_session(conn, player_id: player.id)
    {:ok, view, _} = live(conn, "/arena")
    assert has_element?(view, "#resume-arena-match[href='/matches/#{pending.id}']")
    refute has_element?(view, "#arena-daily-limit")
    refute has_element?(view, "#enter-arena-button")
    refute has_element?(view, "#arena-entry-reward")

    Game.Matches.update!(pending, %{phase: "scored", winner_id: player.id, rewards: %{attacker_pvp_points: 0}})
    {:ok, finished, _} = live(conn, "/arena")
    assert has_element?(finished, "#arena-daily-limit strong", "Daily matches complete")
    refute has_element?(finished, "#resume-arena-match")
    refute has_element?(finished, "#arena-daily-limit.btn")
  end

  test "empty team states guide creation and available-hero browsing", %{conn: conn} do
    hero = create_base_hero()
    conn = init_test_session(conn, player_id: hero.player_id)
    {:ok, view, _} = live(conn, "/arena/edit")
    assert has_element?(view, "#arena-no-teams")
    assert has_element?(view, "#arena-no-selected-team")
    assert has_element?(view, "#arena-no-heroes #arena-browse-available")

    view |> element("#arena-browse-available") |> render_click()
    assert has_element?(view, "#available-heroes-button.active")

    view |> form("#arena-team-form", %{"team" => %{"name" => "New lineup"}}) |> render_submit()
    refute has_element?(view, "#arena-no-teams")
    refute has_element?(view, "#arena-no-selected-team")
    assert has_element?(view, "#arena-team-empty")
  end

  test "empty history and match pick tabs show clear next actions", %{conn: conn} do
    hero = create_base_hero()
    opponent = create_player!()
    conn = init_test_session(conn, player_id: hero.player_id)
    {:ok, arena, _} = live(conn, "/arena")
    assert has_element?(arena, "#arena-no-matches")
    assert has_element?(arena, "#arena-no-duels")

    match = create_match(hero.player, opponent)
    {:ok, view, _} = live(conn, "/matches/#{match.id}")
    assert has_element?(view, "#match-pick-status .hud-notice-counter", "0")
    refute has_element?(view, "#start-match-button")
    assert has_element?(view, "#match-no-trained-heroes #match-browse-available")
    assert has_element?(view, "#match-no-teams a[href='/arena/edit']")
    view |> element("#match-browse-available") |> render_click()
    assert has_element?(view, "#available-heroes.active.show")

    {:ok, base, _} = live(conn, "/base")
    base |> element("#finished-heroes-btn") |> render_click()
    assert has_element?(base, "#base-no-heroes a[href='/invoke']")
    base |> element("#in-progress-heroes-btn") |> render_click()
    refute has_element?(base, "#base-no-heroes")
  end

  test "a full match lineup shows a clear start action", %{conn: conn} do
    player = create_player!()
    opponent = create_player!()
    picks = for index <- 1..5, do: Game.create_hero!(%{name: "Hero #{index}"}, player, base_avatar(), base_skills())
    match = create_match(player, opponent, %{player_picks: Enum.map(picks, & &1.id)})
    {:ok, view, _} = live(init_test_session(conn, player_id: player.id), "/matches/#{match.id}")

    assert has_element?(view, "#match-pick-status-title", "Lineup ready")
    assert has_element?(view, "#start-match-button[phx-click=start].battle-primary")
  end

  defp create_match(player, opponent, attrs \\ %{}) do
    Game.Matches.create!(
      Map.merge(
        %{
          player_id: player.id,
          opponent_id: opponent.id,
          player_picks: [],
          opponent_picks: [],
          generated_picks: [],
          type: "manual"
        },
        attrs
      )
    )
  end
end
