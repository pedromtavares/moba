defmodule MobaWeb.V2.TutorialDesignLiveTest do
  use MobaWeb.ConnCase
  import Phoenix.LiveViewTest

  test "preview first battle uses the modern guide and advances training", %{conn: conn} do
    hero = create_base_hero()
    Game.update_tutorial_step!(hero.player, 1)
    target = hero |> Game.list_targets() |> hd()
    conn = init_test_session(conn, player_id: hero.player_id)

    {:ok, view, _} = live(conn, "/training")
    assert has_element?(view, "#tutorial-step-1[data-preview=true][phx-hook=TutorialStep]")
    refute has_element?(view, ".farm-tabs")

    view |> element("#gank-#{target.id}") |> render_click()
    battle = Engine.latest_battle(hero.id)
    assert_redirect(view, "/battles/#{battle.id}")
    assert Game.get_player!(hero.player_id).tutorial_step == 2
  end

  test "preview shop lesson advances through purchases and can be skipped", %{conn: conn} do
    hero = create_base_hero(%{gold: 800})
    Game.update_tutorial_step!(hero.player, 2)
    conn = init_test_session(conn, player_id: hero.player_id)

    {:ok, view, _} = live(conn, "/training")
    render_click(view, "tutorial3", %{})
    assert has_element?(view, "#tutorial-step-3[data-preview=true]")
    assert has_element?(view, "#shop-modal.d-block .normal-items")

    for code <- ["boots_of_speed", "sages_mask"] do
      view |> element(".normal-items .code-#{code}") |> render_click()
      view |> element(".normal-items button[phx-click=buy]") |> render_click()
    end

    assert has_element?(view, "#tutorial-step-4[data-preview=true]")
    assert has_element?(view, "#shop-modal.d-none")
    assert length(Game.get_hero!(hero.id).items) == 2
    render_click(view, "tutorial5", %{})
    assert has_element?(view, "#tutorial-step-5[data-preview=true]")
    render_click(view, "finish-tutorial", %{})
    assert has_element?(view, "#tutorial-step-19[data-preview=true]")
    assert length(Game.get_hero!(hero.id).items) == 2
  end

  test "preview Base chapter keeps progression and completion events", %{conn: conn} do
    hero = create_base_hero()
    Game.update_tutorial_step!(hero.player, 19)
    conn = init_test_session(conn, player_id: hero.player_id)

    {:ok, view, _} = live(conn, "/base")
    assert has_element?(view, "#tutorial-step-20[data-preview=true]")
    assert has_element?(view, "#pve-progression")
    render_click(view, "tutorial1", %{})
    assert has_element?(view, "#tutorial-step-21[data-preview=true]")
    render_click(view, "finish-tutorial", %{})
    assert Game.get_player!(hero.player_id).tutorial_step == 39
  end

  test "canonical routes use the redesigned tutorial", %{conn: conn} do
    hero = create_base_hero()
    Game.update_tutorial_step!(hero.player, 1)
    conn = init_test_session(conn, player_id: hero.player_id)

    {:ok, view, _} = live(conn, "/training")
    assert has_element?(view, "#tutorial-step-1[data-preview=true]")
    refute has_element?(view, ".farm-tabs")
  end

  test "all farming tabs return after the first tutorial step", %{conn: conn} do
    hero = create_base_hero()
    Game.update_tutorial_step!(hero.player, 2)
    conn = init_test_session(conn, player_id: hero.player_id)

    {:ok, view, _} = live(conn, "/training")

    for id <- ["farm-tab-battle", "farm-tab-meditation", "farm-tab-mine"] do
      assert has_element?(view, ".farm-tabs ##{id}")
    end
  end

  test "preview Arena skips retired lessons without entering matchmaking", %{conn: conn} do
    for step <- [29, 30, 31] do
      hero = create_base_hero()
      Game.update_tutorial_step!(hero.player, step)
      session = init_test_session(conn, player_id: hero.player_id)

      {:ok, view, _} = live(session, "/arena")
      refute has_element?(view, "[phx-hook=TutorialStep]")
      assert has_element?(view, "#enter-arena-button")
      assert Game.get_player!(hero.player_id).tutorial_step == 39
      assert Game.list_matches(hero.player) == []

      render_click(view, "finish-tutorial", %{})
      assert Game.list_matches(hero.player) == []
    end
  end

  test "preview match skips an unfinished lineup lesson", %{conn: conn} do
    player = create_player!(%{tutorial_step: 31})
    opponent = create_player!()

    match =
      Game.Matches.create!(%{
        player_id: player.id,
        opponent_id: opponent.id,
        player_picks: [],
        opponent_picks: [],
        generated_picks: [],
        type: "manual"
      })

    {:ok, view, _} = live(init_test_session(conn, player_id: player.id), "/matches/#{match.id}")
    refute has_element?(view, "[phx-hook=TutorialStep]")
    assert has_element?(view, "#picks-card")
    assert Game.get_player!(player.id).tutorial_step == 39
    assert Game.get_match!(match.id).player_picks == []
  end
end
