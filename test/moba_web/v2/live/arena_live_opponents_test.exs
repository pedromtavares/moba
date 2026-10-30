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

    {:ok, view, _} = live(init_test_session(conn, player_id: player.id), "/arena")
    assert has_element?(view, "#arena-live-section #arena-live-pvp")
    assert has_element?(view, "#arena-live-section #duel-player-#{opponent.id}", "54 SP")
    assert has_element?(view, "#arena-live-opponents a[href='/player/#{opponent.id}']")
    assert has_element?(view, "#can-duel-#{opponent.id}[phx-value-id='#{opponent.id}']:not([disabled])", "Challenge")
    assert has_element?(view, "#arena-duel-history-heading", "Duel history")
    assert has_element?(view, "#arena-duel-history-section #arena-duels-table")
    assert has_element?(view, "#arena-header-footer #season-duel-button[phx-click='season-duel']")
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

      {:ok, view, _} = live(init_test_session(conn, player_id: player.id), "/arena")
      assert has_element?(view, "#cannot-duel-#{opponent.id}[disabled]", "Cooldown")
      refute has_element?(view, "#can-duel-#{opponent.id}")
      assert Game.list_duels(player) == []
    end
  end
end
