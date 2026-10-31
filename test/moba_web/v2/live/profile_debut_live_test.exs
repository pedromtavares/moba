defmodule MobaWeb.V2.ProfileDebutLiveTest do
  use MobaWeb.ConnCase
  import Phoenix.LiveViewTest

  test "the owner can continue an unfinished hero from the empty record", %{conn: conn} do
    hero = create_base_hero()
    {:ok, view, _} = live(init_test_session(conn, player_id: hero.player_id), "/player/#{hero.player_id}")

    assert has_element?(
             view,
             "#profile-arena-debut[data-owner=true][data-state=training]",
             "Your Arena story starts here"
           )

    assert has_element?(view, "#profile-debut-action[href='/training']", "Continue training")
    assert has_element?(view, "#profile-debut-hero[href='/hero/#{hero.id}']", hero.avatar.name)
    assert has_element?(view, "#profile-actions")
    refute has_element?(view, "#profile-matches-table, #profile-duels-table, .profile-history-switcher")
  end

  test "an owner without a hero can start a new training run", %{conn: conn} do
    player = create_player!()
    {:ok, view, _} = live(init_test_session(conn, player_id: player.id), "/player/#{player.id}")

    assert has_element?(view, "#profile-debut-action[href='/invoke']", "Train a new hero")
    refute has_element?(view, "#profile-debut-hero")
  end

  test "a finished hero below Platinum prompts the owner to train another hero", %{conn: conn} do
    hero = create_base_hero(%{finished_at: Timex.now(), league_tier: 2})
    {:ok, view, _} = live(init_test_session(conn, player_id: hero.player_id), "/player/#{hero.player_id}")

    assert has_element?(view, "#profile-arena-debut[data-state=train]")
    assert has_element?(view, "#profile-debut-action[href='/invoke']", "Train a new hero")
    assert has_element?(view, "#profile-debut-hero", "Gold League")
  end

  test "a finished Platinum or higher hero can enter the Arena", %{conn: conn} do
    for tier <- 3..6 do
      hero = create_base_hero(%{finished_at: Timex.now(), league_tier: tier})
      {:ok, view, _} = live(init_test_session(conn, player_id: hero.player_id), "/player/#{hero.player_id}")

      assert has_element?(view, "#profile-arena-debut[data-state=ready]")
      assert has_element?(view, "#profile-debut-action[href='/arena']", "Enter Arena")
    end
  end

  test "other players see the debut and hero without another player's actions", %{conn: conn} do
    viewer = create_player!()

    for {attrs, description} <- [
          {nil, "Their adventure is just beginning."},
          {%{}, "Training their first contender."},
          {%{finished_at: Timex.now(), league_tier: 3}, "Ready for their first Arena battle."}
        ] do
      player = create_player!()
      hero = attrs && create_base_hero(attrs, player)
      {:ok, view, _} = live(init_test_session(conn, player_id: viewer.id), "/player/#{player.id}")

      assert has_element?(view, "#profile-arena-debut[data-owner=false]", "Arena debut awaits")
      assert has_element?(view, "#profile-arena-debut", description)
      refute has_element?(view, "#profile-debut-action, #profile-actions")

      if hero do
        assert has_element?(view, "#profile-debut-hero[href='/hero/#{hero.id}']")
      else
        refute has_element?(view, "#profile-debut-hero")
      end
    end
  end

  test "the first completed 5v5 replaces the debut on a ranking refresh", %{conn: conn} do
    hero = create_base_hero(%{finished_at: Timex.now(), league_tier: 3})
    opponent = create_player!()
    {:ok, view, _} = live(init_test_session(conn, player_id: hero.player_id), "/player/#{hero.player_id}")
    assert has_element?(view, "#profile-arena-debut")

    match =
      Game.Matches.create!(%{
        player_id: hero.player_id,
        opponent_id: opponent.id,
        type: "manual",
        phase: "scored",
        player_picks: [],
        opponent_picks: [],
        generated_picks: [],
        rewards: %{attacker_pvp_points: 0}
      })

    send(view.pid, {"ranking", %{}})

    refute has_element?(view, "#profile-arena-debut")
    assert has_element?(view, "#profile-matches-table a[href='/matches/#{match.id}']")
  end

  test "the first completed 1v1 replaces the debut and selects its history", %{conn: conn} do
    hero = create_base_hero(%{finished_at: Timex.now(), league_tier: 3})
    opponent = create_player!()
    {:ok, view, _} = live(init_test_session(conn, player_id: hero.player_id), "/player/#{hero.player_id}")

    duel = Game.Duels.create!(hero.player, opponent, true)
    Game.Duels.finish!(duel, %{winner: hero.player, attacker_pvp_points: 5, defender_pvp_points: 0})
    send(view.pid, {"ranking", %{}})

    refute has_element?(view, "#profile-arena-debut, #profile-matches-table")
    assert has_element?(view, "#profile-duels-table a[href='/arena/#{duel.id}']")
  end
end
