defmodule MobaWeb.V2.ArenaLiveOpponentsTest do
  use MobaWeb.ConnCase
  import Phoenix.LiveViewTest

  test "live opponents have challenge actions and remain separate from finished duel history", %{conn: conn} do
    player = create_player!()
    previous_opponent = create_player!()
    duel = Game.create_duel!(player, previous_opponent, false)
    Game.Duels.finish!(duel, %{winner: player, attacker_pvp_points: 5, defender_pvp_points: -5})
    player = Game.set_player_available!(Game.get_player!(player.id))
    opponent = create_player!(%{status: "available", pvp_points: 54})
    Accounts.set_online_now(Game.get_player!(opponent.id).user)
    MobaWeb.Presence.track_player(self(), opponent)

    {:ok, view, _} = live(log_in_player(conn, player_id: player.id), "/arena")
    assert has_element?(view, "#arena-live-section #arena-live-pvp")
    assert has_element?(view, "#arena-live-section #duel-player-#{opponent.id}", "54 AR")
    assert has_element?(view, "#duel-player-#{opponent.id} [title='Arena Rating'][data-toggle=tooltip]", "54 AR")
    assert has_element?(view, "#arena-live-opponents a[href='/player/#{opponent.id}']")
    assert has_element?(view, "#can-duel-#{opponent.id}[phx-value-id='#{opponent.id}']:not([disabled])", "Challenge")
    assert has_element?(view, "#arena-live-heading", "Live 1v1")
    assert has_element?(view, "#arena-live-section .ui-swords")
    view |> element("#arena-history-duels-tab") |> render_click()
    assert has_element?(view, "#matchmaking-container #arena-duel-history-section #arena-duels-table")
    assert has_element?(view, "#pvp-progression .arena-play-actions #season-duel-button[phx-click='season-duel']")
    refute has_element?(view, "#arena-duel-history-section #season-duel-button")
    refute has_element?(view, "#arena-live-opponents h3")
    refute has_element?(view, "#arena-live-section #arena-duels-table")
    refute has_element?(view, "#arena-duels-table #duel-player-#{opponent.id}")

    view |> element("#can-duel-#{opponent.id}") |> render_click()
    child = find_live_child(view, "duel-challenges")
    assert has_element?(child, "#duel-challenge-overlay[data-state=pending]")
    assert length(Game.list_duels(player)) == 1
  end

  test "either player's challenge cooldown disables the live challenge action", %{conn: conn} do
    for cooling_down <- [:player, :opponent] do
      player = create_player!(%{status: "available"})
      opponent = create_player!(%{status: "available"})
      Accounts.set_online_now(Game.get_player!(opponent.id).user)
      cooling_player = if cooling_down == :player, do: player, else: opponent
      Game.update_player!(cooling_player, %{last_challenge_at: Timex.now()})
      MobaWeb.Presence.track_player(self(), opponent)

      {:ok, view, _} = live(log_in_player(conn, player_id: player.id), "/arena")
      assert has_element?(view, "#cannot-duel-#{opponent.id}[disabled]", "Cooldown")
      refute has_element?(view, "#can-duel-#{opponent.id}")
      assert Game.list_duels(player) == []
    end
  end

  test "availability toggles refresh other players and synchronize the player's other tabs", %{conn: conn} do
    viewer = create_player!(%{status: "available"})
    opponent = create_player!(%{status: "unavailable"})
    session = log_in_player(conn, player_id: viewer.id)
    {:ok, first_tab, _} = live(session, "/arena")
    {:ok, second_tab, _} = live(session, "/arena")
    {:ok, opponent_tab, _} = live(log_in_player(conn, player_id: opponent.id), "/arena")
    refute has_element?(first_tab, "#duel-player-#{opponent.id}")

    render_click(opponent_tab, "set-status", %{"value" => "on"})
    assert has_element?(first_tab, "#duel-player-#{opponent.id}")
    assert has_element?(second_tab, "#duel-player-#{opponent.id}")

    render_click(first_tab, "set-status", %{})
    refute has_element?(second_tab, "#set-status[checked]")
    refute has_element?(second_tab, "#duel-player-#{opponent.id}")
    render_click(first_tab, "set-status", %{"value" => "on"})
    assert has_element?(second_tab, "#set-status[checked]")
    assert has_element?(second_tab, "#duel-player-#{opponent.id}")

    render_click(opponent_tab, "set-status", %{})
    refute has_element?(first_tab, "#duel-player-#{opponent.id}")
    refute has_element?(second_tab, "#duel-player-#{opponent.id}")
  end

  test "presence changes immediately after mounting are never discarded", %{conn: conn} do
    viewer = create_player!(%{status: "available"})
    opponent = create_player!(%{status: "available"})
    {:ok, view, _} = live(log_in_player(conn, player_id: viewer.id), "/arena")
    refute has_element?(view, "#duel-player-#{opponent.id}")

    {:ok, _} = MobaWeb.Presence.track_player(self(), opponent)
    send(view.pid, %{event: "presence_diff"})
    assert has_element?(view, "#duel-player-#{opponent.id}")

    :ok = MobaWeb.Presence.untrack(self(), "online", opponent.id)
    send(view.pid, %{event: "presence_diff"})
    refute has_element?(view, "#duel-player-#{opponent.id}")
  end
end
