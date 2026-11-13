defmodule MobaWeb.V2.HudStatesLiveTest do
  use MobaWeb.ConnCase
  import Phoenix.LiveViewTest

  test "pending duel resumes from its play button and history remains available", %{conn: conn} do
    hero = create_base_hero()
    opponent = create_player!()
    completed = Game.create_duel!(hero.player, opponent, false)
    Game.Duels.finish!(completed, %{winner: hero.player, attacker_pvp_points: 5, defender_pvp_points: -5})
    pending = Game.create_duel!(hero.player, opponent, false)
    conn = log_in_player(conn, player_id: hero.player_id)
    {:ok, view, _} = live(conn, "/arena")

    assert has_element?(view, "#pvp-progression #resume-arena-duel", "Resume 1v1")
    assert has_element?(view, "#set-status[disabled]")
    view |> element("#arena-history-duels-tab") |> render_click()
    assert has_element?(view, "#resume-arena-duel[href='/arena/#{pending.id}']")
    refute has_element?(view, "#pvp_duels a.col-xl-4")
    assert has_element?(view, "#arena-duels-table a[href='/arena/#{completed.id}']")
    refute has_element?(view, "#arena-duels-table a[href='/arena/#{pending.id}']")
  end

  test "3v3 resumes a pending match at the limit and allows new matches after the daily reset", %{conn: conn} do
    hero = create_base_hero()
    player = Game.update_player!(hero.player, %{daily_matches: Moba.daily_match_limit()})
    opponent = create_player!()
    last_reset = DateTime.utc_now() |> DateTime.add(-3600) |> DateTime.truncate(:second)
    season = Game.update_season!(Game.current_season(), %{last_pvp_update_at: last_reset})

    for _ <- 1..(Moba.daily_match_limit() - 1) do
      create_match(player, opponent, %{phase: "scored", winner_id: player.id, rewards: %{attacker_pvp_points: 0}})
    end

    pending = create_match(player, opponent)
    conn = log_in_player(conn, player_id: player.id)
    {:ok, view, _} = live(conn, "/arena")
    assert has_element?(view, "#resume-arena-match[href='/matches/#{pending.id}']")
    refute has_element?(view, "#arena-daily-limit")
    refute has_element?(view, "#enter-arena-button")
    refute has_element?(view, "#arena-entry-reward")

    Game.Matches.update!(pending, %{phase: "scored", winner_id: player.id, rewards: %{attacker_pvp_points: 0}})
    {:ok, finished, _} = live(conn, "/arena")
    deadline = last_reset |> DateTime.add(86_400) |> DateTime.to_unix(:millisecond)
    assert has_element?(finished, "#arena-reset-countdown[role=timer][data-reset-at='#{deadline}']", "Resets in")
    assert has_element?(finished, "#enter-arena-button[disabled]", "3v3 daily limit reached")
    assert has_element?(finished, "#season-duel-button:not([disabled])", "Play 1v1")
    refute has_element?(finished, "#arena-entry-reward")
    refute has_element?(finished, "#resume-arena-match")
    refute has_element?(finished, "#arena-daily-limit.btn")

    Game.update_season!(season, %{last_pvp_update_at: DateTime.add(last_reset, -86_400)})
    reset_season = Conductor.pvp_tick!()
    send(finished.pid, {"ranking", %{}})

    new_deadline = reset_season.last_pvp_update_at |> DateTime.add(86_400) |> DateTime.to_unix(:millisecond)
    assert has_element?(finished, "#arena-reset-countdown[data-reset-at='#{new_deadline}']")
    assert has_element?(finished, "#enter-arena-button:not([disabled])", "Play 3v3")
  end

  test "empty team states guide creation and training", %{conn: conn} do
    hero = create_base_hero()
    conn = log_in_player(conn, player_id: hero.player_id)
    {:ok, view, _} = live(conn, "/arena/edit")
    assert has_element?(view, "#arena-no-teams")
    assert has_element?(view, "#arena-no-selected-team")
    assert has_element?(view, "#arena-no-heroes a[href='/new']")

    refute has_element?(view, "#available-heroes-button")

    view |> form("#arena-team-form", %{"team" => %{"name" => "New lineup"}}) |> render_submit()
    refute has_element?(view, "#arena-no-teams")
    refute has_element?(view, "#arena-no-selected-team")
    assert has_element?(view, "#arena-team-empty")
  end

  test "empty history and match pick tabs show clear next actions", %{conn: conn} do
    hero = create_base_hero()
    opponent = create_player!()
    conn = log_in_player(conn, player_id: hero.player_id)
    {:ok, arena, _} = live(conn, "/arena")
    assert has_element?(arena, "#arena-no-matches")
    arena |> element("#arena-history-duels-tab") |> render_click()
    assert has_element?(arena, "#arena-no-duels")

    match = create_match(hero.player, opponent)
    {:ok, view, _} = live(conn, "/matches/#{match.id}")
    assert has_element?(view, "#match-empty-slot-1")
    assert has_element?(view, "#start-match-button[disabled]")
    assert has_element?(view, ".arena-draft-hero-list a[href='/new']")
    assert has_element?(view, "#edit-teams-button[href='/arena/edit?match_id=#{match.id}']")
    refute has_element?(view, "#available-heroes-button")

    {:ok, base, _} = live(conn, "/base")
    base |> element("#base-toggle-runs") |> render_click()
    assert has_element?(base, "#base-no-heroes a[href='/new']")
    base |> element("#base-toggle-runs") |> render_click()
    refute has_element?(base, "#base-no-heroes")
  end

  test "a full match lineup shows a clear start action", %{conn: conn} do
    player = create_player!()
    opponent = create_player!()
    picks = for index <- 1..3, do: Game.create_hero!(%{name: "Hero #{index}"}, player, base_avatar(), base_skills())
    match = create_match(player, opponent, %{player_picks: Enum.map(picks, & &1.id)})
    {:ok, view, _} = live(log_in_player(conn, player_id: player.id), "/matches/#{match.id}")

    refute has_element?(view, "#arena-player-lineup .arena-draft-empty")
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
