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

    {:ok, view, html} = live(conn, "/v2/arena/#{duel.id}")
    assert html =~ "turn to pick"

    assert has_element?(view, "[id^=hero_]")
    assert has_element?(view, "#battle-bar")
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

    {:ok, view, html} = live(conn, "/v2/arena/#{duel.id}")

    assert html =~ "Winner:"
    assert html =~ "#{duel.player.user.username}: +5 SP"
    assert html =~ "#{duel.opponent_player.user.username}: -5 SP"
    refute has_element?(view, "#battle-bar")
  end
end
