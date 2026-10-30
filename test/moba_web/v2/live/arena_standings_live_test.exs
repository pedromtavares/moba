defmodule MobaWeb.V2.ArenaStandingsLiveTest do
  use MobaWeb.ConnCase
  import Phoenix.LiveViewTest

  setup do
    Cachex.del(:game_cache, "daily_ranking")
    on_exit(fn -> Cachex.del(:game_cache, "daily_ranking") end)
    :ok
  end

  test "bracket selection filters standings and keeps the player's own position", %{conn: conn} do
    player = create_player!(%{pvp_tier: 0, ranking: 26, daily_wins: 2, daily_matches: 5})
    immortal = create_player!(%{pvp_tier: 2, ranking: 1, daily_wins: 8, daily_matches: 10})
    Cachex.put(:game_cache, "daily_ranking", [immortal, player])
    {:ok, view, _} = live(init_test_session(conn, player_id: player.id), "/arena")

    assert has_element?(view, "#arena-bracket-plebs[aria-pressed=true]")
    assert has_element?(view, "#standing-player-#{player.id}.is-you .arena-standing-position", "26")
    assert has_element?(view, "#standing-player-#{player.id} .arena-standing-score strong", "2")
    assert has_element?(view, "#standing-player-#{player.id} a[href='/player/#{player.id}'][aria-current=true]")
    refute has_element?(view, "#arena-your-standing")
    refute has_element?(view, "#arena-ranking-table, #immortal-ranking-button")

    view |> element("#arena-bracket-immortals") |> render_click()
    assert has_element?(view, "#arena-bracket-immortals[aria-pressed=true]")
    assert has_element?(view, "#arena-bracket-plebs[aria-pressed=false]")
    assert has_element?(view, "#standing-player-#{immortal.id} .arena-standing-score strong", "8")
    refute has_element?(view, "#standing-player-#{player.id}")
    assert has_element?(view, "#arena-your-standing", "Plebs")
    assert has_element?(view, "#arena-your-standing .arena-standing-position", "26")

    view |> element("#arena-bracket-shadows") |> render_click()
    assert has_element?(view, "#arena-bracket-shadows[aria-pressed=true]")
    assert has_element?(view, "#arena-standings-empty")
    assert has_element?(view, "#arena-your-standing")

    view |> element("#arena-bracket-plebs") |> render_click()
    assert has_element?(view, "#standing-player-#{player.id}.is-you")
    refute has_element?(view, "#arena-your-standing, #arena-standings-empty")
  end

  test "an unranked player's standing remains visible and legacy standings keep their table", %{conn: conn} do
    player = create_player!()
    Cachex.put(:game_cache, "daily_ranking", [])
    conn = init_test_session(conn, player_id: player.id)
    {:ok, view, _} = live(conn, "/arena")
    assert has_element?(view, "#arena-your-standing [aria-label=Unranked]")
    assert has_element?(view, "#arena-standings-empty")
  end
end
