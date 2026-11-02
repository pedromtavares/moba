defmodule MobaWeb.V2.DuelDesignLiveTest do
  use MobaWeb.ConnCase
  import Phoenix.LiveViewTest

  test "pick, wait, battle and final-pick states keep their controls and phase tracker", %{conn: conn} do
    player = create_player!()
    opponent = create_player!()
    hero = Game.create_hero!(%{name: "Player Hero"}, player, strong_avatar(), base_skills())
    other = Game.create_hero!(%{name: "Opponent Hero"}, opponent, weak_avatar(), base_skills())
    duel = Game.create_duel!(player, opponent, false)
    conn = log_in_player(conn, player_id: player.id)
    {:ok, view, _} = live(conn, "/arena/#{duel.id}")

    assert has_element?(view, "#duel-status[data-your-turn=true]")
    assert has_element?(view, "#duel-pick-timer[role=timer]")
    assert has_element?(view, "#duel-hero-selection [phx-click=pick]")
    assert has_element?(view, "#battle-bar li[aria-current=step]", "First pick")

    pick_id =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#duel-hero-selection [phx-value-id]")
      |> LazyHTML.attribute("phx-value-id")
      |> hd()
      |> String.to_integer()

    view |> element("#pick-hero-#{pick_id}") |> render_click()
    assert Game.get_duel!(duel.id).player_first_pick_id == pick_id
    assert has_element?(view, "#duel-page[data-phase=opponent_first_pick]")
    refute has_element?(view, "#duel-hero-selection")

    Game.continue_duel!(Game.get_duel!(duel.id), other)
    assert has_element?(view, "#duel-page[data-phase=player_battle]")
    battle = duel.id |> Game.get_duel!() |> Engine.first_duel_battle()
    assert has_element?(view, "#duel-enter-battle[href='/battles/#{battle.id}']")
    refute has_element?(view, "#duel-pick-timer")
    Engine.auto_finish_battle!(battle)
    assert has_element?(view, "#duel-round-2")
    assert has_element?(view, "#duel-review-battle-#{battle.id}")
    assert has_element?(view, "#duel-round-1 .resource-gauge[aria-label$=health]")

    Game.continue_duel!(Game.get_duel!(duel.id), other)
    assert has_element?(view, "#duel-page[data-phase=player_second_pick] #duel-hero-selection")
    Game.continue_duel!(Game.get_duel!(duel.id), hero)
    duel = Game.get_duel!(duel.id)
    final = Engine.last_duel_battle(duel)
    Engine.auto_finish_battle!(final)
    assert has_element?(view, "#duel-page[data-phase=finished]")
    assert has_element?(view, "#duel-banner.duel-finished-banner #duel-status #duel-rewards")
    assert has_element?(view, "#duel-banner #duel-rematch[phx-click=rematch][data-game-fullscreen]")
    refute has_element?(view, "#duel-return-arena")
    assert has_element?(view, "#duel-banner .duel-score")
    assert has_element?(view, ".duel-finished-chat #duel-message-form")
    refute has_element?(view, ".duel-command-row #duel-status")
    refute has_element?(view, "#battle-bar")
    refute has_element?(view, "#duel-hero-selection")
  end

  test "season duels omit live chat and chat submissions clear the input", %{conn: conn} do
    player = create_player!()
    opponent = create_player!()
    duel = Game.create_duel!(player, opponent, false)
    conn = log_in_player(conn, player_id: player.id)
    {:ok, view, _} = live(conn, "/arena/#{duel.id}")
    view |> form("#duel-message-form", %{"message" => %{"body" => "Good luck!"}}) |> render_submit()
    assert has_element?(view, "#duel-messages .duel-message", "Good luck!")
    refute has_element?(view, "#duel-message-form input[value='Good luck!']")

    Game.Duels.finish!(duel, %{winner: nil})
    auto = Game.create_duel!(player, opponent, true)
    {:ok, season, _} = live(conn, "/arena/#{auto.id}")
    refute has_element?(season, "#duel-message-form")
    assert has_element?(season, ".duel-score", "Season duel")

    Game.Duels.finish!(auto, %{winner: player, attacker_pvp_points: 2, defender_pvp_points: 0})
    send(season.pid, {"phase", %{}})
    assert has_element?(season, "#duel-banner.duel-finished-banner #duel-status h1", "wins")
    assert has_element?(season, "#duel-banner #duel-rewards", "+2 AR")
    assert has_element?(season, "#duel-rewards strong[title='Arena Rating'][data-toggle=tooltip]", "+2 AR")
    assert has_element?(season, "#duel-return-arena[href='/arena']")
    refute has_element?(season, "#duel-rematch")
    refute has_element?(season, ".duel-command-row")
  end

  test "finished live duels can be rematched while players retain their unavailable duel status", %{conn: conn} do
    player = create_player!()
    opponent = create_player!()
    duel = Game.create_duel!(player, opponent, false)
    Game.Duels.finish!(duel, %{winner: nil, attacker_pvp_points: 0, defender_pvp_points: 0})
    assert Game.get_player!(player.id).status == "unavailable"
    assert Game.get_player!(opponent.id).status == "unavailable"
    conn = log_in_player(conn, player_id: player.id)
    {:ok, view, _} = live(conn, "/arena/#{duel.id}")

    assert has_element?(view, "#duel-status h1", "Duel drawn")
    assert has_element?(view, "#duel-rewards strong", "0 AR")
    assert has_element?(view, "#duel-rewards strong[title='Arena Rating'][data-toggle=tooltip]", "0 AR")
    refute has_element?(view, "#duel-return-arena")
    view |> element("#duel-rematch") |> render_click()
    child = find_live_child(view, "duel-challenges")
    assert has_element?(child, "#duel-challenge-overlay[data-state=pending] #duel-challenge-close")
    assert length(Game.list_duels(player)) == 1
  end

  test "spectators and active or season duels cannot send a rematch challenge", %{conn: conn} do
    player = create_player!()
    opponent = create_player!()
    viewer = create_player!()
    duel = Game.create_duel!(player, opponent, false)

    for {viewing_player, duel} <- [
          {player, duel},
          {player, Game.Duels.create!(player, opponent, true)},
          {viewer,
           player
           |> Game.Duels.create!(opponent, false)
           |> Game.Duels.finish!(%{winner: nil, attacker_pvp_points: 0, defender_pvp_points: 0})}
        ] do
      {:ok, view, _} = live(log_in_player(conn, player_id: viewing_player.id), "/arena/#{duel.id}")
      refute has_element?(view, "#duel-rematch")
      render_click(view, "rematch", %{})
      child = find_live_child(view, "duel-challenges")
      refute has_element?(child, "#duel-challenge-overlay")
    end
  end

  test "casual results keep their badge and omit season-point rewards", %{conn: conn} do
    player = create_player!(%{pvp_points: 100})
    opponent = create_player!(%{pvp_points: 1000})
    duel = Game.create_duel!(player, opponent, false)
    Game.Duels.finish!(duel, %{winner: player, attacker_pvp_points: 0, defender_pvp_points: 0})
    {:ok, view, _} = live(log_in_player(conn, player_id: player.id), "/arena/#{duel.id}")

    assert has_element?(view, ".duel-casual", "Casual")
    assert has_element?(view, "#duel-status h1", "wins")
    refute has_element?(view, "#duel-rewards")
  end
end
