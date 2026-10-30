defmodule MobaWeb.V2.ArenaStandingsLiveTest do
  use MobaWeb.ConnCase
  import Phoenix.LiveViewTest

  setup do
    Cachex.del(:game_cache, "daily_ranking")
    on_exit(fn -> Cachex.del(:game_cache, "daily_ranking") end)
    :ok
  end

  test "5v5 uses the full profile daily ranking across all brackets", %{conn: conn} do
    player = create_player!(%{pvp_tier: 0, ranking: 26, daily_wins: 2, daily_matches: 5})
    immortal = create_player!(%{pvp_tier: 2, ranking: 1, daily_wins: 8, daily_matches: 10})
    shadow = create_player!(%{pvp_tier: 1, ranking: 6, daily_wins: 3})
    Cachex.put(:game_cache, "daily_ranking", [immortal, shadow, player])
    {:ok, view, _} = live(init_test_session(conn, player_id: player.id), "/arena")

    assert has_element?(view, "#arena-history-matches-tab", "5v5")
    assert has_element?(view, "#arena-history-duels-tab", "1v1")
    assert has_element?(view, "#arena-standings-5v5[aria-pressed=true]")
    assert has_element?(view, "#standing-player-#{player.id}.is-you .arena-standing-position", "26")
    assert has_element?(view, "#standing-player-#{player.id} .arena-standing-score strong", "2")
    assert has_element?(view, "#standing-player-#{player.id} a[href='/player/#{player.id}'][aria-current=true]")
    assert standings_ids(view) == Enum.map([immortal, shadow, player], &"standing-player-#{&1.id}")

    assert has_element?(
             view,
             "#standing-player-#{immortal.id} [data-bracket=Immortals] .arena-standing-bracket",
             "Immortals"
           )

    assert has_element?(view, "#standing-player-#{shadow.id} [data-bracket=Shadows] .arena-standing-bracket", "Shadows")
    assert has_element?(view, "#standing-player-#{player.id} [data-bracket=Plebs] .arena-standing-bracket", "Plebs")

    assert has_element?(
             view,
             "#standing-player-#{shadow.id} .arena-standing-movement[data-direction=up] .ui-chevrons-up"
           )

    assert has_element?(view, "#standing-player-#{player.id} .arena-standing-movement[data-direction=up]")
    refute has_element?(view, "#arena-your-standing, #arena-bracket-group, #arena-ranking-table")
  end

  test "1v1 sorts season points rather than season score or daily rank", %{conn: conn} do
    player = create_player!(%{pvp_points: 10_000_001, pvp_tier: 0, ranking: 26, daily_wins: 1})

    composite_leader =
      create_player!(%{pvp_points: 10_000_000, best_immortal_streak: 100_000, pve_tier: 10, ranking: 1, daily_wins: 30})

    bot = create_player!(%{pvp_points: 99_999_999}, create_user(), "Ranking bot")
    guest = Game.create_player!(%{pvp_points: 99_999_999})
    Cachex.put(:game_cache, "daily_ranking", [composite_leader, player])
    {:ok, view, _} = live(init_test_session(conn, player_id: player.id), "/arena")

    view |> element("#arena-standings-1v1") |> render_click()
    assert has_element?(view, "#arena-standings-1v1[aria-pressed=true]")
    assert has_element?(view, "#arena-standings-list[aria-label='Season points descending']")
    assert Enum.take(standings_ids(view), 2) == Enum.map([player, composite_leader], &"standing-player-#{&1.id}")
    assert has_element?(view, "#standing-player-#{player.id} .arena-standing-position", "1")
    assert has_element?(view, "#standing-player-#{player.id} .arena-standing-score strong", "10000001")
    assert has_element?(view, "#standing-player-#{player.id} .arena-standing-score span", "season points")
    refute has_element?(view, "#arena-standings .arena-standing-row[data-bracket]")
    refute has_element?(view, "#arena-standings .arena-standing-movement")
    refute has_element?(view, "#standing-player-#{bot.id}, #standing-player-#{guest.id}")
    assert has_element?(view, "#arena-history-matches-tab[aria-pressed=true]")

    view |> element("#arena-history-duels-tab") |> render_click()
    send(view.pid, {"ranking", %{}})
    assert has_element?(view, "#arena-standings-1v1[aria-pressed=true]")
    assert has_element?(view, "#arena-history-duels-tab[aria-pressed=true]")

    view |> element("#arena-standings-5v5") |> render_click()
    assert standings_ids(view) == Enum.map([composite_leader, player], &"standing-player-#{&1.id}")
    assert has_element?(view, "#standing-player-#{player.id} .arena-standing-position", "26")
    assert has_element?(view, "#standing-player-#{player.id} .arena-standing-score strong", "1")
  end

  test "an unranked player's daily standing remains visible", %{conn: conn} do
    player = create_player!()
    Cachex.put(:game_cache, "daily_ranking", [])
    {:ok, view, _} = live(init_test_session(conn, player_id: player.id), "/arena")
    assert has_element?(view, "#arena-your-standing [aria-label=Unranked]")
    assert has_element?(view, "#arena-standings-empty")
    refute has_element?(view, "#arena-your-standing .arena-standing-movement")
  end

  test "5v5 projections include the actual promotion and relegation boundaries", %{conn: conn} do
    incumbent = create_player!(%{pvp_tier: 2, ranking: 1, daily_wins: 4, pvp_points: 20})
    leader = create_player!(%{pvp_tier: 2, ranking: 2, daily_wins: 5, pvp_points: 10})
    other_immortal = create_player!(%{pvp_tier: 2, ranking: 5, daily_wins: 1})

    placements = [
      {1, 6, :up, "Immortals"},
      {1, 9, :up, "Immortals"},
      {1, 10, nil, nil},
      {1, 19, nil, nil},
      {1, 20, :down, "Plebs"},
      {1, 25, :down, "Plebs"},
      {0, 26, :up, "Shadows"},
      {0, 31, :up, "Shadows"},
      {0, 32, nil, nil}
    ]

    rows =
      Enum.map(placements, fn {tier, rank, direction, bracket} ->
        {create_player!(%{pvp_tier: tier, ranking: rank}), direction, bracket}
      end)

    Cachex.put(:game_cache, "daily_ranking", [incumbent, leader, other_immortal] ++ Enum.map(rows, &elem(&1, 0)))
    {:ok, view, _} = live(init_test_session(conn, player_id: incumbent.id), "/arena")

    for {player, direction, bracket} <- rows do
      if direction do
        action = if direction == :up, do: "promotion", else: "relegation"
        label = "Projected #{action} to #{bracket} at the next daily reset"

        assert has_element?(
                 view,
                 "#standing-player-#{player.id} .arena-standing-movement[data-direction=#{direction}][aria-label='#{label}'][title='#{label}']"
               )
      else
        refute has_element?(view, "#standing-player-#{player.id} .arena-standing-movement")
      end
    end

    assert has_element?(
             view,
             "#standing-player-#{leader.id} .arena-standing-movement[aria-label*='promotion to The Immortal']"
           )

    assert has_element?(
             view,
             "#standing-player-#{incumbent.id} .arena-standing-movement[data-direction=down] .ui-chevrons-down"
           )

    assert has_element?(
             view,
             "#standing-player-#{other_immortal.id} .arena-standing-movement[aria-label*='relegation to Shadows']"
           )

    updated = Game.update_player!(incumbent, %{daily_wins: 6})
    Cachex.put(:game_cache, "daily_ranking", [updated, leader, other_immortal])
    send(view.pid, {"ranking", %{}})
    refute has_element?(view, "#standing-player-#{incumbent.id} .arena-standing-movement")
    assert has_element?(view, "#standing-player-#{leader.id} .arena-standing-movement[data-direction=down]")
  end

  test "the personal standing footer includes projected movement", %{conn: conn} do
    player = create_player!(%{pvp_tier: 0, ranking: 31})
    Cachex.put(:game_cache, "daily_ranking", [])
    {:ok, view, _} = live(init_test_session(conn, player_id: player.id), "/arena")
    assert has_element?(view, "#arena-your-standing .arena-standing-movement[aria-label*='promotion to Shadows']")
  end

  defp standings_ids(view) do
    view
    |> element("#arena-standings-list")
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("li")
    |> LazyHTML.attribute("id")
  end
end
