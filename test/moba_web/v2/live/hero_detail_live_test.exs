defmodule MobaWeb.V2.HeroDetailLiveTest do
  use MobaWeb.ConnCase
  import Phoenix.LiveViewTest

  test "owner detail keeps the loadout, plain stats and skin navigation", %{conn: conn} do
    hero = create_base_hero() |> Game.buy_item!(base_item())
    conn = conn |> log_in_user(hero.player.user) |> put_session(:player_id, hero.player_id)
    {:ok, view, _} = live(conn, "/hero/#{hero.id}")

    assert has_element?(view, "#hero-detail-name", hero.name)
    assert has_element?(view, "#hero-detail-loadout #skill-#{hd(hero.skills).id}-#{hero.id}")
    assert has_element?(view, "#hero-detail-loadout #item-#{hd(hero.items).id}-#{hero.id}")
    assert has_element?(view, "#hero-detail-stats .hero-stats")
    refute has_element?(view, "#hero-detail-stats button")
    assert has_element?(view, "#hero-view-skins[href^='/tavern?']")
    assert has_element?(view, "#hero-detail-player[href='/player/#{hero.player_id}']")
    assert has_element?(view, "#hero-training-status[data-finished='false']")
    assert has_element?(view, "#hero-detail-duration", "#{hero.pve_current_turns + hero.pve_total_turns}")
  end

  test "owners open customization on demand and closing resets the HUD", %{conn: conn} do
    hero = create_base_hero()
    conn = init_test_session(conn, player_id: hero.player_id)
    {:ok, view, _} = live(conn, "/hero/#{hero.id}")

    refute has_element?(view, "#hero-bar")
    refute has_element?(view, "#hero-review.content-with-hero-bar")
    assert has_element?(view, "#customize-hero[aria-expanded=false]", "Customize hero")
    view |> element("#customize-hero") |> render_click()
    assert has_element?(view, "#customize-hero[aria-expanded=true]", "Close customization")
    assert has_element?(view, "#hero-review.content-with-hero-bar")
    assert has_element?(view, "#hero-bar #edit-button")
    view |> element("#edit-button") |> render_click()
    view |> element("#toggle-shop") |> render_click()
    assert has_element?(view, "#shop-modal.d-block")

    view |> element("#customize-hero") |> render_click()
    refute has_element?(view, "#hero-bar")
    refute has_element?(view, "#shop-modal")
    view |> element("#customize-hero") |> render_click()
    assert has_element?(view, "#hero-bar #edit-button")
    refute has_element?(view, "#hero-bar #save-button")
    assert has_element?(view, "#shop-modal.d-none")

    other = create_base_hero()
    render_patch(view, "/hero/#{other.id}")
    refute has_element?(view, "#customize-hero")
    refute has_element?(view, "#hero-bar")
  end

  test "guest owners can open their hero HUD", %{conn: conn} do
    hero = create_base_hero(%{}, Game.create_player!(%{user_id: nil}))
    {:ok, view, _} = live(init_test_session(conn, player_id: hero.player_id), "/hero/#{hero.id}")
    refute has_element?(view, "#hero-detail-player")
    refute has_element?(view, "#hero-bar")
    view |> element("#customize-hero") |> render_click()
    assert has_element?(view, "#hero-bar")
  end

  test "another player's hero has a profile link without owner controls", %{conn: conn} do
    hero = create_base_hero()
    viewer = create_base_hero()
    conn = conn |> log_in_user(viewer.player.user) |> put_session(:player_id, viewer.player_id)
    {:ok, view, _} = live(conn, "/hero/#{hero.id}")

    assert has_element?(view, "#hero-detail-player[href='/player/#{hero.player_id}']")
    refute has_element?(view, "#hero-detail-skins")
    refute has_element?(view, "#customize-hero")
    render_click(view, "toggle-customize")
    refute has_element?(view, "#hero-bar")
  end

  test "finished unranked hero remains visible below the leaderboard with capped time", %{conn: conn} do
    hero = create_base_hero(%{finished_at: Timex.now()})
    inserted_at = hero.finished_at |> DateTime.add(-8 * 86400) |> DateTime.to_naive()
    hero = hero |> Ecto.Changeset.change(inserted_at: inserted_at) |> Moba.Repo.update!()
    conn = conn |> log_in_user(hero.player.user) |> put_session(:player_id, hero.player_id)
    {:ok, view, _} = live(conn, "/hero/#{hero.id}")

    assert has_element?(view, "#hero-training-status[data-finished='true']")
    assert has_element?(view, "#hero-detail-duration", "99+")
    assert has_element?(view, "#ranking-#{hero.id} [aria-label='Unranked']")
    assert has_element?(view, "#hero-leaderboard tfoot #ranking-#{hero.id}[data-current='true']")
    assert has_element?(view, "#ranking-#{hero.id} a[aria-current='page']")
    assert has_element?(view, "#hero-league-title", Moba.leagues()[hero.league_tier])
  end

  test "switching rankings shows the league position and the separate global rank", %{conn: conn} do
    hero = create_base_hero(%{finished_at: Timex.now(), league_tier: 4, pve_ranking: 1981})
    global_leader = create_base_hero(%{finished_at: Timex.now(), league_tier: 6, pve_ranking: 1})
    Cachex.put(:game_cache, "pve_ranking", [global_leader])
    on_exit(fn -> Cachex.del(:game_cache, "pve_ranking") end)
    conn = conn |> log_in_user(hero.player.user) |> put_session(:player_id, hero.player_id)
    {:ok, view, _} = live(conn, "/hero/#{hero.id}")

    assert has_element?(view, "#hero-leaderboard tbody #ranking-#{hero.id} .hero-ranking-position", "#1")
    assert has_element?(view, "#hero-ranking-standing", "of 1 run")
    assert has_element?(view, "#hero-ranking-league-tab[aria-pressed=true]")
    refute has_element?(view, "#ranking-#{global_leader.id}")

    view |> element("#hero-ranking-global-tab") |> render_click()
    assert has_element?(view, "#hero-ranking-global-tab[aria-pressed=true]")
    assert has_element?(view, "#hero-leaderboard-title", "Global rankings")
    assert has_element?(view, "#hero-leaderboard tfoot #ranking-#{hero.id} .hero-ranking-position", "#1981")
    assert has_element?(view, "#ranking-#{global_leader.id} .hero-ranking-position", "#1")
    assert has_element?(view, "#hero-league-milestone")

    view |> element("#hero-ranking-league-tab") |> render_click()
    assert has_element?(view, "#ranking-#{hero.id} .hero-ranking-position", "#1")
    assert Game.get_hero!(hero.id).pve_ranking == 1981
  end

  test "league standings include only peers and explain the next account unlock", %{conn: conn} do
    hero = create_base_hero(%{finished_at: Timex.now(), league_tier: 4, pve_tier: 0, total_gold_farm: 10_000})
    peer = create_base_hero(%{finished_at: Timex.now(), league_tier: 4, total_gold_farm: 20_000})
    higher = create_base_hero(%{finished_at: Timex.now(), league_tier: 6, total_gold_farm: 30_000})
    {:ok, view, _} = live(init_test_session(conn, player_id: hero.player_id), "/hero/#{hero.id}")

    assert has_element?(view, "#hero-leaderboard-title", "Diamond League rankings")
    assert has_element?(view, "#ranking-#{hero.id} .hero-ranking-position", "#2")
    assert has_element?(view, "#ranking-#{peer.id} .hero-ranking-position", "#1")
    refute has_element?(view, "#ranking-#{higher.id}")
    assert has_element?(view, "#hero-league-milestone-title", "Unlock Master League")
    assert has_element?(view, "#hero-league-milestone", "2 different Avatars")
  end

  test "an unfinished run has an inviting empty state and ranks when training completes", %{conn: conn} do
    hero = create_base_hero(%{league_tier: 2})
    {:ok, view, _} = live(init_test_session(conn, player_id: hero.player_id), "/hero/#{hero.id}")

    assert has_element?(view, "#hero-league-empty")
    assert has_element?(view, "#hero-league-placement", "Finish training")
    assert has_element?(view, "#hero-leaderboard tfoot #ranking-#{hero.id} [aria-label=Unranked]")
    assert has_element?(view, "#hero-league-milestone-title", "Reach Platinum League")

    Game.update_hero!(hero, %{finished_at: Timex.now()})
    send(view.pid, {"hero", %{id: hero.id}})

    assert has_element?(view, "#hero-ranking-standing strong", "#1")
    refute has_element?(view, "#hero-league-empty")
    refute has_element?(view, "#hero-league-placement")
    refute has_element?(view, "#hero-leaderboard tfoot")
  end

  test "Grandmaster milestones cover imperfect and perfect runs", %{conn: conn} do
    hero = create_base_hero(%{finished_at: Timex.now(), league_tier: 6, pve_tier: 2})
    {:ok, view, _} = live(init_test_session(conn, player_id: hero.player_id), "/hero/#{hero.id}")
    assert has_element?(view, "#hero-league-milestone-title", "Aim for a perfect 60K")

    Game.update_hero!(hero, %{total_xp_farm: 30_000, total_gold_farm: 30_000})
    send(view.pid, {"hero", %{id: hero.id}})
    assert has_element?(view, "#hero-league-milestone-title", "Master another avatar")
  end

  test "every earlier league offers its next challenge when unlocked", %{conn: conn} do
    player = create_player!(%{pve_tier: 2})

    for tier <- 0..5 do
      hero = create_base_hero(%{league_tier: tier, pve_tier: 2}, Game.get_player!(player.id))
      {:ok, view, _} = live(init_test_session(conn, player_id: player.id), "/hero/#{hero.id}")

      assert has_element?(view, "#hero-league-milestone-title", "Reach #{Moba.leagues()[tier + 1]}")

      if tier == 5 do
        assert has_element?(view, "#hero-league-milestone", "Defeat Roshan")
      end
    end
  end

  test "Master runs explain the Grandmaster account unlock", %{conn: conn} do
    player = create_player!(%{pve_tier: 1})
    hero = create_base_hero(%{league_tier: 5, pve_tier: 1, finished_at: Timex.now()}, player)
    {:ok, view, _} = live(init_test_session(conn, player_id: player.id), "/hero/#{hero.id}")

    assert has_element?(view, "#hero-league-milestone-title", "Unlock Grandmaster League")
    assert has_element?(view, "#hero-league-milestone", "5 different Avatars")
  end

  test "a ranked hero is highlighted in the leaderboard without a duplicate footer", %{conn: conn} do
    hero = create_base_hero(%{finished_at: Timex.now(), pve_ranking: 1})
    Cachex.put(:game_cache, "pve_ranking", [hero])
    on_exit(fn -> Cachex.del(:game_cache, "pve_ranking") end)
    conn = conn |> log_in_user(hero.player.user) |> put_session(:player_id, hero.player_id)
    {:ok, view, _} = live(conn, "/hero/#{hero.id}")

    assert has_element?(view, "#ranking-#{hero.id} .hero-ranking-position", "#1")
    assert has_element?(view, "#hero-leaderboard tbody #ranking-#{hero.id}[data-current='true']")
    refute has_element?(view, "#hero-leaderboard tfoot")
  end

  test "an old completed Gold run gets a league rank even without a global rank", %{conn: conn} do
    hero = create_base_hero(%{finished_at: ~U[2021-01-01 12:00:00Z], league_tier: 2})
    hero = hero |> Ecto.Changeset.change(inserted_at: ~N[2021-01-01 11:30:00]) |> Moba.Repo.update!()
    {:ok, view, _} = live(init_test_session(conn, player_id: hero.player_id), "/hero/#{hero.id}")

    assert has_element?(view, "#hero-leaderboard-title", "Gold League rankings")
    assert has_element?(view, "#ranking-#{hero.id} .hero-ranking-position", "#1")
    assert has_element?(view, ".hero-leaderboard-heading", "All-time completed runs")
    view |> element("#hero-ranking-global-tab") |> render_click()
    assert has_element?(view, "#ranking-#{hero.id} [aria-label=Unranked]")
    assert has_element?(view, "#hero-global-placement")
  end

  test "Bronze and Silver offer global rankings and explain the Gold threshold", %{conn: conn} do
    for tier <- 0..1 do
      hero = create_base_hero(%{league_tier: tier})
      {:ok, view, _} = live(init_test_session(conn, player_id: hero.player_id), "/hero/#{hero.id}")
      assert has_element?(view, "#hero-ranking-league-tab[disabled]")
      assert has_element?(view, "#hero-ranking-global-tab[aria-pressed=true]")
      assert has_element?(view, "#hero-ranking-minimum-league", "League rankings begin at Gold")
      render_click(view, "ranking-tab", %{"type" => "league"})
      assert has_element?(view, "#hero-ranking-global-tab[aria-pressed=true]")
    end
  end
end
