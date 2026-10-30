defmodule MobaWeb.V2.TrainingHeaderLiveTest do
  use MobaWeb.ConnCase
  import Phoenix.LiveViewTest

  test "alive, dead, farming and history share the same training overview", %{conn: conn} do
    hero = create_base_hero(%{pve_tier: 4, pve_current_turns: 3, refresh_targets_count: 2})
    conn = init_test_session(conn, player_id: hero.player_id)
    {:ok, alive, _} = live(conn, "/training")
    reference = alive |> element(".training-header") |> render() |> LazyHTML.from_fragment()

    for state <- ["alive", "dead", "mining", "meditating"] do
      Game.update_hero!(Game.get_hero!(hero.id), %{
        pve_state: state,
        pve_farming_turns: 1,
        pve_farming_started_at: Timex.now()
      })

      for path <- ["/training", "/battles"] do
        {:ok, view, _} = live(conn, path)
        header = view |> element(".training-header") |> render() |> LazyHTML.from_fragment()

        assert LazyHTML.text(LazyHTML.query(header, ".ascent-heading h2, .ascent-track, .ascent-farm")) ==
                 LazyHTML.text(LazyHTML.query(reference, ".ascent-heading h2, .ascent-track, .ascent-farm"))

        assert LazyHTML.attribute(LazyHTML.query(header, "img"), "src") ==
                 LazyHTML.attribute(LazyHTML.query(reference, "img"), "src")

        if path == "/battles" do
          assert has_element?(view, ".training-header #history-return-training[href='/training']")
          refute has_element?(view, "#training-battle-log")
        else
          assert has_element?(view, ".training-header #training-battle-log[href='/battles']")
          refute has_element?(view, "#history-return-training")
        end

        if path == "/training" && state != "dead" do
          assert has_element?(view, ".training-header #training-refresh-targets[title='2 refreshes remaining']")
          assert has_element?(view, ".training-header #show-farm-tabs[role=switch][checked]")
        else
          refute has_element?(view, "#training-refresh-targets")
          refute has_element?(view, "#show-farm-tabs")
        end
      end
    end
  end

  test "pending battles retain the training overview", %{conn: conn} do
    hero = create_base_hero(%{pve_tier: 4})
    # A human-controlled defender keeps the fixture pending regardless of bot rolls.
    battle = Engine.create_pve_battle!(%{attacker: hero, defender: create_base_hero(), difficulty: "moderate"})
    refute battle.finished
    conn = init_test_session(conn, player_id: hero.player_id)
    {:ok, view, _} = live(conn, "/training")

    assert has_element?(view, ".training-header #current-training-rank")
    assert has_element?(view, ".training-header #training-battle-log")
    assert has_element?(view, "#training-ascent-status", "Battle in progress")
    refute has_element?(view, ".training-header #show-farm-tabs")
    refute has_element?(view, ".training-header #training-refresh-targets")
    assert has_element?(view, "#resume-pending-battle[href='/battles/#{battle.id}']", "Resume battle")
  end

  test "history header returns to training in the same preview scope", %{conn: conn} do
    hero = create_base_hero(%{pve_tier: 4})
    conn = init_test_session(conn, player_id: hero.player_id)
    {:ok, history, _} = live(conn, "/battles")

    {:ok, training, _} =
      history
      |> element(".training-header #history-return-training")
      |> render_click()
      |> follow_redirect(conn, "/training")

    assert has_element?(training, "#training-battle-log[href='/battles']")
    assert has_element?(training, "#show-farm-tabs")
  end

  test "league ascent shows turn progress and unlocks a functional challenge", %{conn: conn} do
    hero = create_base_hero(%{pve_current_turns: 3, pve_total_turns: 15})
    Game.update_tutorial_step!(hero.player, 20)
    conn = init_test_session(conn, player_id: hero.player_id)
    {:ok, view, _} = live(conn, "/training")

    assert has_element?(view, "#training-ascent-title", "Road to Diamond")
    assert has_element?(view, "#current-training-rank[aria-current=step]", "Bronze")
    assert has_element?(view, ".ascent-turns[aria-label='2 of 5 turns spent']")
    assert has_element?(view, ".ascent-pip.is-spent:nth-child(2)")
    refute has_element?(view, ".ascent-pip.is-spent:nth-child(3)")
    refute has_element?(view, "#start-league-challenge")
    refute has_element?(view, "#training-ascent.is-challenge-stage")
    view |> element("#farm-tab-mine") |> render_click()

    Game.update_hero!(hero, %{pve_current_turns: 0})
    refute has_element?(view, "#farm-activity")
    {:ok, ready, _} = live(conn, "/training")
    assert has_element?(ready, "#training-ascent.is-challenge-stage")
    refute has_element?(ready, "#farm-tab-battle, #farm-tab-meditation, #farm-tab-mine, #show-farm-tabs")
    assert has_element?(ready, "#training-ascent-status", "Silver challenge unlocked")
    assert has_element?(ready, ".ascent-turns[aria-label='5 of 5 turns spent']")
    assert has_element?(ready, "#training-ascent #start-league-challenge")
    ready |> element("#start-league-challenge") |> render_click()
    assert_redirect(ready)
    assert Game.get_hero!(hero.id).league_step == 1
  end

  test "history, dead and farming states never offer an unavailable challenge", %{conn: conn} do
    hero = create_base_hero(%{pve_current_turns: 0, pve_total_turns: 15})
    conn = init_test_session(conn, player_id: hero.player_id)
    {:ok, history, _} = live(conn, "/battles")
    refute has_element?(history, "#start-league-challenge")
    refute has_element?(history, "#training-ascent.is-challenge-stage")

    for state <- ["dead", "mining", "meditating"] do
      Game.update_hero!(Game.get_hero!(hero.id), %{
        pve_state: state,
        pve_farming_turns: 1,
        pve_farming_started_at: Timex.now()
      })

      {:ok, view, _} = live(conn, "/training")
      refute has_element?(view, "#start-league-challenge")
      refute has_element?(view, "#training-ascent.is-ready")
    end
  end

  test "advanced league tracks include their goal without an invalid next badge", %{conn: conn} do
    for {tier, goal} <- [{1, 5}, {4, 6}] do
      hero = create_base_hero(%{pve_tier: tier, league_tier: 4, pve_current_turns: 3})
      conn = init_test_session(conn, player_id: hero.player_id)
      {:ok, view, _} = live(conn, "/training")
      assert has_element?(view, ".ascent-track img[src='/images/league/#{goal}.png']")
      refute has_element?(view, ".ascent-track img[src='/images/league/#{goal + 1}.png']")
    end

    hero = create_base_hero(%{pve_tier: 4, league_tier: 6, pve_current_turns: 0})
    conn = init_test_session(conn, player_id: hero.player_id)
    {:ok, history, _} = live(conn, "/battles")
    assert has_element?(history, "#training-ascent-status", "Grandmaster reached")
    refute has_element?(history, "img[src='/images/league/7.png']")
  end
end
