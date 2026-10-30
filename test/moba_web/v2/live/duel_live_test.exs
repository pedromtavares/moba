defmodule MobaWeb.V2.DuelLiveTest do
  use MobaWeb.ConnCase

  import Phoenix.LiveViewTest

  test "renders the v2 duel and allows the opening pick", %{conn: conn} do
    player = create_player!()
    opponent = create_player!()
    skills = base_skills()

    Game.create_hero!(%{name: "Player Hero"}, player, strong_avatar(), skills)
    _opponent_hero = Game.create_hero!(%{name: "Opponent Hero"}, opponent, weak_avatar(), skills)
    duel = Game.create_duel!(player, opponent, false)

    conn =
      conn
      |> init_test_session(player_id: player.id)

    {:ok, view, _html} = live(conn, "/arena/#{duel.id}")
    assert has_element?(view, "#duel-status[data-your-turn=true]", "Your pick")

    assert has_element?(view, "[id^=hero_]")
    assert has_element?(view, "#battle-bar")
    assert has_element?(view, "#duel-hero-selection .league-logo")
    assert has_element?(view, ".hero-stats .text-orange[title='Speed']")
    refute has_element?(view, ".duel-pending-battle-card")
  end

  test "pending duel battle offers the redesigned enter battle action", %{conn: conn} do
    player = create_player!()
    opponent = create_player!()
    skills = base_skills()

    player_hero = Game.create_hero!(%{name: "Player Hero"}, player, strong_avatar(), skills)
    opponent_hero = Game.create_hero!(%{name: "Opponent Hero"}, opponent, weak_avatar(), skills)

    duel = Game.create_duel!(player, opponent, false)
    Game.continue_duel!(duel, player_hero)
    duel = Game.get_duel!(duel.id)
    Game.continue_duel!(duel, opponent_hero)
    duel = Game.get_duel!(duel.id)
    battle = Engine.first_duel_battle(duel)

    conn =
      conn
      |> init_test_session(player_id: player.id)

    {:ok, view, _html} = live(conn, "/arena/#{duel.id}")

    assert has_element?(
             view,
             ~s|#loading-battle-#{battle.id}.battle-primary[phx-hook="Loading"][href="/battles/#{battle.id}"]|
           )
  end

  test "shows duel rewards after completion", %{conn: conn} do
    player = create_player!()
    opponent = create_player!()
    skills = base_skills()

    player_hero = Game.create_hero!(%{name: "Player Hero"}, player, strong_avatar(), skills)
    opponent_hero = Game.create_hero!(%{name: "Opponent Hero"}, opponent, weak_avatar(), skills)

    duel = Game.create_duel!(player, opponent, false)
    Game.continue_duel!(duel, player_hero)
    duel = Game.get_duel!(duel.id)
    Game.continue_duel!(duel, opponent_hero)
    duel = Game.get_duel!(duel.id)
    duel |> Engine.first_duel_battle() |> Engine.auto_finish_battle!()
    duel = Game.get_duel!(duel.id)
    Game.continue_duel!(duel, opponent_hero)
    duel = Game.get_duel!(duel.id)
    Game.continue_duel!(duel, player_hero)
    duel = Game.get_duel!(duel.id)
    duel |> Engine.last_duel_battle() |> Engine.auto_finish_battle!()

    conn =
      conn
      |> init_test_session(player_id: player.id)

    duel = Game.get_duel!(duel.id)

    {:ok, view, _html} = live(conn, "/arena/#{duel.id}")

    assert has_element?(view, "#duel-status h1", "#{duel.winner_player.user.username} wins")
    assert has_element?(view, "#duel-rewards > span:first-child", duel.player.user.username)
    assert has_element?(view, "#duel-rewards > span:first-child strong", "+5 SP")
    assert has_element?(view, "#duel-rewards > span:last-child", duel.opponent_player.user.username)
    assert has_element?(view, "#duel-rewards > span:last-child strong", "-5 SP")
    refute has_element?(view, "#battle-bar")
  end

  test "clears duel chat input after sending a message", %{conn: conn} do
    player = create_player!()
    opponent = create_player!()
    skills = base_skills()

    Game.create_hero!(%{name: "Player Hero"}, player, strong_avatar(), skills)
    Game.create_hero!(%{name: "Opponent Hero"}, opponent, weak_avatar(), skills)
    duel = Game.create_duel!(player, opponent, false)

    conn =
      conn
      |> init_test_session(player_id: player.id)

    {:ok, view, _html} = live(conn, "/arena/#{duel.id}")

    html =
      view
      |> form("#duel-message-form", %{"message" => %{"body" => "hello"}})
      |> render_submit()

    assert has_element?(view, ~s|#duel-message-form[phx-hook="ResetOnSubmit"]|)
    refute html =~ ~s|value="hello"|
  end
end
