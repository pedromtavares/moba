defmodule MobaWeb.V2.DashboardLiveTest do
  use MobaWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Test.TeamHelper

  describe "team cards" do
    test "cards show reward mode and average farm without graying fallen heroes", %{conn: conn} do
      {scope, player} = team_account()
      record = team_run(scope, player)

      {:ok, record} =
        Game.TeamRuns.update(scope, record, fn run ->
          heroes =
            Map.new(run.heroes, fn {id, unit} ->
              {id, %{unit | hero: %{unit.hero | total_gold_farm: 6000, total_xp_farm: 6000, pve_state: "dead"}}}
            end)

          %{run | heroes: heroes, league_tier: 6, reward_mode: :focus, phase: :finished}
        end)

      conn = conn |> log_in_user(scope.user) |> put_session(:player_id, player.id)
      {:ok, view, _} = live(conn, "/base")
      card = "#visible-team-#{record.id}"
      assert has_element?(view, "#{card} .hero-card-meta", "Focus")
      assert has_element?(view, "#{card} .team-card-farm strong", "12K")
      assert has_element?(view, "#{card} .team-card-farm small", "Avg farm")
      refute has_element?(view, "#{card} .is-fallen")
      refute has_element?(view, "#{card} .hero-card-meta", "Grandmaster")
    end

    test "deleting a team removes it persistently and cannot affect another account", %{conn: conn} do
      {scope, player} = team_account()
      record = team_run(scope, player)
      {other_scope, other_player} = team_account()
      other = team_run(other_scope, other_player)
      conn = conn |> log_in_user(scope.user) |> put_session(:player_id, player.id)
      {:ok, view, _} = live(conn, "/base")

      assert has_element?(view, "#visible-team-#{record.id} .hero-card-meta", "Shared")
      render_click(view, "archive-team", %{"id" => to_string(other.id)})
      assert Game.TeamRuns.get!(other_scope, other.id).archived_at == nil
      assert has_element?(view, "#visible-team-#{record.id}")

      view |> element("#base-team-delete-#{record.id}") |> render_click()
      refute has_element?(view, "#visible-team-#{record.id}")
      assert Moba.Repo.get!(Game.Schema.TrainingTeam, record.id).archived_at
      assert Game.TeamRuns.active(scope, player.id) == nil
      assert Game.TeamRuns.latest(scope, player.id) == nil
      assert_raise Ecto.NoResultsError, fn -> Game.TeamRuns.get!(scope, record.id) end

      {:ok, reloaded, _} = live(conn, "/base")
      refute has_element?(reloaded, "#visible-team-#{record.id}")
    end

    test "deleting a completed team preserves its collected heroes and public result", %{conn: conn} do
      {scope, player} = team_account()
      record = team_run(scope, player)
      {:ok, finished} = Game.TeamRuns.update(scope, record, &%{&1 | phase: :finished})
      collection = Game.Heroes.collection_for(player.id) |> Enum.map(& &1.hero_id)
      conn = conn |> log_in_user(scope.user) |> put_session(:player_id, player.id)
      {:ok, view, _} = live(conn, "/base")

      view |> element("#base-team-delete-#{finished.id}") |> render_click()
      refute has_element?(view, "#visible-team-#{finished.id}")
      assert Game.TeamRuns.profile!(scope, finished.id).hero_ids == finished.hero_ids
      assert Enum.map(Game.Heroes.collection_for(player.id), & &1.hero_id) == collection
      assert Enum.all?(Game.get_heroes(finished.hero_ids), &is_nil(&1.archived_at))
    end

    test "teams share the hero grid and each opens its own run", %{conn: conn} do
      {scope, player} = team_account()
      first = team_run(scope, player)
      second = team_run(scope, player)
      {other_scope, other_player} = team_account()
      other = team_run(other_scope, other_player)
      conn = conn |> log_in_user(scope.user) |> put_session(:player_id, player.id)
      {:ok, view, _} = live(conn, "/base")

      assert has_element?(view, "#base-invoke-btn[href='/new']", "Start training")
      refute has_element?(view, "#base-resume-team, #base-no-heroes")
      refute has_element?(view, "#visible-team-#{other.id}")

      for record <- [first, second] do
        card = "#hero-list-unfinished #visible-team-#{record.id}"
        assert has_element?(view, "#{card} .team-training-card")
        assert has_element?(view, "#{card} #base-team-continue-#{record.id}[href='/training?run=#{record.id}']")

        assert view
               |> element("#{card} .team-card-roster")
               |> render()
               |> LazyHTML.from_fragment()
               |> LazyHTML.query(".team-card-hero")
               |> Enum.count() == 3

        for unit <- Game.TeamTraining.team(Game.TeamRuns.state(record)) do
          assert has_element?(view, "#{card} .team-card-identity", unit.hero.avatar.name)
        end
      end

      {:ok, training, _} =
        view |> element("#base-team-continue-#{first.id}") |> render_click() |> follow_redirect(conn)

      assert has_element?(training, "#team-training-page")
    end

    test "completed teams appear together and their collected heroes are not duplicated", %{conn: conn} do
      {scope, player} = team_account()
      record = team_run(scope, player)
      {:ok, finished} = Game.TeamRuns.update(scope, record, &%{&1 | phase: :finished})
      active = team_run(scope, player)
      solo = create_base_hero(%{name: "Solo training"}, Game.get_player!(player.id))
      conn = conn |> log_in_user(scope.user) |> put_session(:player_id, player.id)
      {:ok, view, _} = live(conn, "/base")

      assert has_element?(view, "#visible-team-#{active.id}")
      assert has_element?(view, "#visible-hero-#{solo.id}")
      refute has_element?(view, "#visible-team-#{finished.id}")
      view |> element("#base-toggle-runs") |> render_click()
      assert has_element?(view, "#hero-list-finished #visible-team-#{finished.id}")
      assert has_element?(view, "#base-team-continue-#{finished.id}[href='/teams/#{finished.id}']", "View team")
      refute has_element?(view, "#visible-team-#{active.id}")

      for id <- finished.hero_ids, do: refute(has_element?(view, "#visible-hero-#{id}"))

      view |> element("#base-toggle-runs") |> render_click()
      view |> element("#visible-hero-#{solo.id} [phx-click=continue]") |> render_click()
      assert_redirect(view, "/training?solo=true")
    end

    test "paginates teams and solo runs together and recovers when the last page is deleted", %{conn: conn} do
      {scope, player} = team_account()
      teams = for _ <- 1..2, do: team_run(scope, player)
      oldest = create_base_hero(%{name: "First solo"}, player)
      newest = create_base_hero(%{name: "Second solo"}, Game.get_player!(player.id))
      abandoned = team_run(scope, player)
      {:ok, _} = Game.TeamRuns.update(scope, abandoned, &%{&1 | phase: :abandoned})
      {:ok, draft} = Game.TeamRuns.draft(scope, player)
      conn = conn |> log_in_user(scope.user) |> put_session(:player_id, player.id)
      {:ok, view, _} = live(conn, "/base")

      for team <- teams, do: assert(has_element?(view, "#visible-team-#{team.id}"))
      assert has_element?(view, "#visible-hero-#{newest.id}")
      refute has_element?(view, "#visible-hero-#{oldest.id}")
      refute has_element?(view, "#visible-team-#{abandoned.id}, #visible-team-#{draft.id}")
      assert has_element?(view, "#base-runs-previous[disabled]")

      view |> element("#base-runs-next") |> render_click()
      assert has_element?(view, "#visible-hero-#{oldest.id}")
      refute has_element?(view, "#visible-hero-#{newest.id}, [id^='visible-team-']")
      assert has_element?(view, "#base-runs-next[disabled]")

      view |> element("#base-runs-previous") |> render_click()
      assert has_element?(view, "#visible-hero-#{newest.id}")

      view |> element("#base-runs-next") |> render_click()
      view |> element("#base-toggle-runs", "Show Finished Runs") |> render_click()
      view |> element("#base-toggle-runs", "Show Pending Runs") |> render_click()
      assert has_element?(view, "#base-runs-previous[disabled]")

      view |> element("#base-runs-next") |> render_click()
      view |> element("#visible-hero-#{oldest.id} [phx-click=archive]") |> render_click()
      assert has_element?(view, "#visible-hero-#{newest.id}")
      refute has_element?(view, "#base-runs-next")
    end
  end

  describe "unauthenticated access" do
    test "redirects to /start without player_id in session", %{conn: conn} do
      conn = get(conn, "/base")
      assert redirected_to(conn) == "/start"
    end
  end

  describe "avatar collection" do
    test "explains the league requirement before the skin purchase controls", %{conn: conn} do
      player = create_player!()
      Accounts.update_user!(Accounts.get_user!(player.user_id), %{shard_count: 1_000})
      avatar = base_avatar()
      [_master, grandmaster | _] = Game.list_avatar_skins(avatar.code)

      {:ok, view, _} = live(log_in_player(conn, player_id: player.id), "/base?avatar=#{avatar.code}")
      view |> element("#base-preview-skin-#{grandmaster.code}") |> render_click()

      assert has_element?(
               view,
               "#base-skin-requirement",
               "Finish a Phantom Assassin run at Grandmaster."
             )

      assert has_element?(
               view,
               "#base-skin-requirement + .base-skin-action-row #base-unlock-skin-#{grandmaster.code}[disabled][aria-describedby=base-skin-requirement]",
               "Unlock for 1000 Shards"
             )
    end

    test "legacy Tavern links open the corresponding Base skin gallery", %{conn: conn} do
      assert redirected_to(get(conn, "/tavern")) == "/base"
      path = redirected_to(get(conn, "/tavern?avatar=phantom_assassin"))
      assert path == "/base?avatar=phantom_assassin"

      hero = create_combat_hero(%{finished_at: Timex.now()})
      {:ok, view, _} = live(log_in_player(conn, player_id: hero.player_id), path)
      assert has_element?(view, "#base-avatar-details[aria-label='Phantom Assassin']")
      assert has_element?(view, ".base-avatar-workspace[data-panel=skins] #base-preview-skin-default")
      view |> element("#base-close-avatar") |> render_click()
      assert_patch(view, "/base")
      refute has_element?(view, "#base-avatar-details")

      view |> element("#base-avatar-tinker") |> render_click()
      assert has_element?(view, "#base-avatar-unlock-preview #base-discord-unlock[href='/auth?origin=base']")
    end

    test "shows only matching completed runs and returns to pending runs", %{conn: conn} do
      {scope, player} = team_account()
      team = team_run(scope, player)
      {:ok, team} = Game.TeamRuns.update(scope, team, &%{&1 | phase: :finished})
      [member | _] = Game.get_heroes(team.hero_ids)
      avatar = member.avatar
      pending = create_base_hero(%{}, player, avatar)
      [older, newer] = for _ <- 1..2, do: create_combat_hero(%{finished_at: Timex.now()}, player, avatar)
      other_avatar = Enum.find(Game.list_creation_avatars(), &(&1.code != avatar.code))
      other = create_combat_hero(%{finished_at: Timex.now()}, player, other_avatar)
      other_owner = create_combat_hero(%{finished_at: Timex.now()}, create_player!(), avatar)

      {:ok, view, _} = live(log_in_player(conn, player_id: player.id), "/base")
      assert has_element?(view, "#hero-list-unfinished #visible-hero-#{pending.id}")
      view |> element("#base-avatar-#{avatar.code}") |> render_click()

      assert has_element?(view, "#base-avatar-#{avatar.code}[aria-pressed=true]")

      assert has_element?(
               view,
               ".base-run-toolbar > .base-avatar-navigation + #base-invoke-btn[href='/new']",
               "Start training"
             )

      assert has_element?(
               view,
               "#base-avatar-details #visible-hero-#{member.id} a[href='/teams/#{team.id}']",
               "View team"
             )

      refute has_element?(view, "#base-avatar-details select")

      refute has_element?(
               view,
               "#visible-hero-#{pending.id}, #visible-hero-#{other.id}, #visible-hero-#{other_owner.id}, #visible-hero-#{newer.id}"
             )

      view |> element(".base-avatar-navigation #base-avatar-runs-next") |> render_click()
      assert has_element?(view, "#base-avatar-details #visible-hero-#{newer.id}")
      refute has_element?(view, "#visible-hero-#{older.id}, #visible-hero-#{member.id}")
      view |> element("#base-avatar-runs-next") |> render_click()
      assert has_element?(view, "#base-avatar-details #visible-hero-#{older.id}")
      assert has_element?(view, "#base-avatar-runs-next[disabled]")

      view |> element(".base-avatar-navigation #base-close-avatar") |> render_click()
      assert has_element?(view, "#hero-list-unfinished #visible-hero-#{pending.id}")
      refute has_element?(view, "#base-avatar-details")
    end

    test "uses existing unlock prices and only equips an owned skin on the chosen run", %{conn: conn} do
      player = create_player!()
      Accounts.update_user!(Accounts.get_user!(player.user_id), %{shard_count: 1_000})
      hero = create_combat_hero(%{league_tier: 6, finished_at: Timex.now()}, player)
      other_run = create_combat_hero(%{league_tier: 6, finished_at: Timex.now()}, player)
      Game.update_hero_collection!(hero)
      [master, grandmaster | _] = Game.list_avatar_skins(hero.avatar.code)

      {:ok, view, _} = live(log_in_player(conn, player_id: player.id), "/base")
      view |> element("#base-avatar-bloodseeker") |> render_click()
      assert has_element?(view, ".base-avatar-navigation #base-close-avatar")
      assert has_element?(view, "#base-avatar-unlock-preview h2", "Bloodseeker")
      assert has_element?(view, "#base-avatar-unlock-preview .avatar-showcase-role", "Bruiser")
      assert has_element?(view, "#base-avatar-unlock-preview .avatar-showcase-ultimate[data-toggle=tooltip]", "Rupture")
      assert has_element?(view, "#base-avatar-unlock-preview progress[aria-label=Defense]")
      assert has_element?(view, "#base-avatar-unlock-preview .base-skin-balance", "Shards available")
      assert has_element?(view, "#base-unlock-avatar-bloodseeker", "150 Shards")
      view |> element("#base-unlock-avatar-bloodseeker") |> render_click()
      assert has_element?(view, "#base-avatar-details", "No completed runs for this avatar yet")
      assert "bloodseeker" in Accounts.unlocked_codes_for(Accounts.get_user!(player.user_id))

      view |> element("#base-avatar-#{hero.avatar.code}") |> render_click()
      assert has_element?(view, ".base-skin-header #base-skin-zoom-button[data-target='#base-skin-zoom']")
      assert has_element?(view, "#base-skin-zoom-close[data-dismiss=modal]")
      assert has_element?(view, ".base-skin-controls #base-preview-skin-default")
      view |> element("#base-preview-skin-#{grandmaster.code}") |> render_click()
      assert has_element?(view, ".base-skin-header h3", grandmaster.name)
      refute has_element?(view, ".base-skin-header", "1000 Shards")
      assert has_element?(view, ".base-skin-header img[alt=Grandmaster]")
      assert has_element?(view, ".base-skin-header a[href='#{grandmaster.author_link}']", grandmaster.author_name)
      art = MobaWeb.V2.Components.GameHelpers.background_url(grandmaster)
      assert has_element?(view, "#base-skin-zoom .base-skin-zoom-viewport img[src='#{art}']")
      assert has_element?(view, "#base-skin-zoom-title", grandmaster.name)

      assert has_element?(
               view,
               ".base-avatar-skins > .base-skin-actions #base-unlock-skin-#{grandmaster.code}[disabled]",
               "Unlock for 1000 Shards"
             )

      assert has_element?(view, ".base-skin-actions .base-skin-balance", "Shards available")
      assert has_element?(view, ".base-avatar-skins > .base-skin-actions .base-skin-balance strong", "850")
      refute has_element?(view, ".base-skin-actions .base-avatar-note, #base-skin-requirement")
      render_click(view, "unlock-skin")
      assert Accounts.get_user!(player.user_id).shard_count == 850

      view |> element("#base-preview-skin-#{master.code}") |> render_click()
      render_click(view, "equip-skin")
      assert Game.get_hero!(hero.id).skin_id == nil
      view |> element("#base-unlock-skin-#{master.code}") |> render_click()
      assert Accounts.get_user!(player.user_id).shard_count == 350
      refute has_element?(view, "#base-unlock-skin-#{master.code}")

      view |> element("#base-avatar-runs-next") |> render_click()
      assert has_element?(view, "#base-avatar-details #visible-hero-#{hero.id}")
      assert has_element?(view, "#base-preview-skin-default[aria-pressed=true]")
      view |> element("#base-preview-skin-#{master.code}") |> render_click()
      view |> element("#base-equip-skin") |> render_click()
      assert Game.get_hero!(hero.id).skin_id == master.id
      assert Game.get_hero!(other_run.id).skin_id == nil
      assert has_element?(view, "#base-equip-skin[disabled]", "Equipped")
      assert has_element?(view, ".base-skin-actions .base-skin-balance strong", "350")

      view |> element("#base-avatar-runs-previous") |> render_click()
      assert has_element?(view, "#base-avatar-details #visible-hero-#{other_run.id}")
      assert has_element?(view, "#base-preview-skin-default[aria-pressed=true]")
      view |> element("#base-avatar-runs-next") |> render_click()
      assert has_element?(view, "#base-preview-skin-#{master.code}[aria-pressed=true]")

      view |> element("#base-preview-skin-default") |> render_click()
      view |> element("#base-equip-skin") |> render_click()
      assert Game.get_hero!(hero.id).skin_id == nil
    end
  end

  describe "connected mount" do
    test "renders pve progression and hero list", %{conn: conn} do
      hero =
        create_base_hero()
        |> Game.buy_item!(base_item())

      conn = conn |> log_in_user(hero.player.user) |> put_session(:player_id, hero.player_id)

      {:ok, view, html} = live(conn, "/base")

      assert html =~ "Start training"
      assert html =~ "Show Finished Runs"
      assert html =~ "id=\"pve-progression\""
      assert has_element?(view, "#visible-hero-#{hero.id} .league-logo")
      assert has_element?(view, "#skill-#{hd(hero.skills).id}-#{hero.id}[title]")
      assert has_element?(view, "#item-#{hd(hero.items).id}-#{hero.id}[title]")
    end

    test "shows unfinished heroes by default when they exist", %{conn: conn} do
      hero = create_base_hero()
      conn = conn |> log_in_user(hero.player.user) |> put_session(:player_id, hero.player_id)

      {:ok, view, _html} = live(conn, "/base")

      assert has_element?(view, "#visible-hero-#{hero.id}")
    end

    test "renders the dashboard navigation controls", %{conn: conn} do
      hero = create_base_hero()
      conn = conn |> log_in_user(hero.player.user) |> put_session(:player_id, hero.player_id)

      {:ok, view, _html} = live(conn, "/base")

      assert has_element?(view, "#base-toggle-runs")
      assert has_element?(view, "#hero-list-unfinished")
    end

    test "does not start a guide for players with an old tutorial state", %{conn: conn} do
      hero = create_base_hero()
      player = Game.update_tutorial_step!(hero.player, 19)
      conn = conn |> log_in_user(player.user) |> put_session(:player_id, player.id)

      {:ok, view, _html} = live(conn, "/base")

      refute has_element?(view, "[phx-hook=TutorialStep]")
    end

    test "guest Base keeps collection and account actions available", %{conn: conn} do
      player = Game.create_player!(%{user_id: nil, tutorial_step: 20})
      hero = create_base_hero(%{name: "Guest Hero"}, player)
      player = Game.update_collection!(player, [%{id: hero.id}])
      conn = conn |> log_in_player(player_id: player.id)

      {:ok, view, _html} = live(conn, "/base")

      assert has_element?(view, "#hero-list-container")
      assert has_element?(view, "#create-account-link")
      refute has_element?(view, "[phx-hook=TutorialStep]")
    end
  end

  describe "filter event" do
    test "switches to finished tab", %{conn: conn} do
      player = create_player!()
      _unfinished = create_base_hero(%{name: "In Progress"}, player)
      player = Game.get_player!(player.id)
      finished = create_base_hero(%{name: "Finished"}, player) |> Game.update_hero!(%{finished_at: Timex.now()})
      user = Accounts.get_user!(player.user_id)

      conn = conn |> log_in_user(user) |> put_session(:player_id, player.id)

      {:ok, view, _html} = live(conn, "/base")

      view |> element("#base-toggle-runs", "Show Finished Runs") |> render_click()

      assert has_element?(view, "#hero-list-finished")
      assert has_element?(view, "#visible-hero-#{finished.id}")
      refute has_element?(view, "#visible-hero-#{player.current_pve_hero_id}")
    end

    test "switches back to unfinished tab", %{conn: conn} do
      player = create_player!()
      unfinished = create_base_hero(%{name: "In Progress"}, player)
      player = Game.get_player!(player.id)
      _finished = create_base_hero(%{name: "Finished"}, player) |> Game.update_hero!(%{finished_at: Timex.now()})
      user = Accounts.get_user!(player.user_id)

      conn = conn |> log_in_user(user) |> put_session(:player_id, player.id)

      {:ok, view, _html} = live(conn, "/base")

      view |> element("#base-toggle-runs", "Show Finished Runs") |> render_click()
      view |> element("#base-toggle-runs", "Show Pending Runs") |> render_click()

      assert has_element?(view, "#hero-list-unfinished")
      assert has_element?(view, "#visible-hero-#{unfinished.id}")
    end
  end

  describe "cinematic base" do
    test "renders the redesigned progression and preserves collection filters", %{conn: conn} do
      hero = create_base_hero() |> Game.buy_item!(base_item())
      player = Game.get_player!(hero.player_id)
      finished = create_base_hero(%{name: "Finished Hero"}, player) |> Game.update_hero!(%{finished_at: Timex.now()})
      Game.update_hero_collection!(finished)
      conn = conn |> log_in_user(player.user) |> put_session(:player_id, player.id)

      {:ok, preview, _html} = live(conn, "/base")
      assert has_element?(preview, "#game-page .base-atmosphere[aria-hidden=true]")
      assert has_element?(preview, "#hero-list-container")

      assert has_element?(preview, "#pve-progression.base-ascent")
      assert has_element?(preview, "#base-rank-0[aria-current=step]")
      assert has_element?(preview, "#base-rank-1.is-next")

      refute has_element?(preview, ".stats-footer")
      assert has_element?(preview, "#skill-#{hd(hero.skills).id}-#{hero.id}[title]")
      assert has_element?(preview, "#item-#{hd(hero.items).id}-#{hero.id}[title]")

      preview |> element("#base-toggle-runs") |> render_click()
      assert has_element?(preview, "#base-toggle-runs", "Show Pending Runs")
      assert has_element?(preview, "#visible-hero-#{finished.id}")
      refute has_element?(preview, "#visible-hero-#{hero.id}")

      preview |> element("#base-toggle-runs") |> render_click()
      assert has_element?(preview, "#base-page.base-page #visible-hero-#{hero.id}")
      assert has_element?(preview, "#base-toggle-runs", "Show Finished Runs")
    end
  end

  test "cinematic progression retains advanced requirements and the final rank", %{conn: conn} do
    player = create_player!(%{pve_tier: 4, pve_progression: %{master_codes: ["phantom_assassin"]}})
    hero = create_base_hero(%{}, player)
    conn = log_in_player(conn, player_id: hero.player_id)
    {:ok, view, _} = live(conn, "/base")

    assert has_element?(view, "#base-rank-4[aria-current=step]")
    assert has_element?(view, "#base-rank-5.is-next[style*='--rank-progress: 0.05']")

    assert has_element?(
             view,
             ".base-ascent-heading .base-ascent-milestone #base-quest-description",
             "20 different Avatars"
           )

    assert has_element?(view, "#pve-progression .base-ascent-track + footer #base-collection img.avatar")
    assert has_element?(view, "#hero-list-container > .base-run-toolbar > #base-invoke-btn[href='/new']")
    refute has_element?(view, "#pve-progression #base-invoke-btn")
    assert has_element?(view, "#base-rank-progress[aria-valuetext='1/20 Avatars'][aria-valuenow='5']")
    assert has_element?(view, "#base-rewards-btn[data-target='#pve-tier-rewards']")

    Game.update_player!(player, %{pve_tier: Moba.max_pve_tier()})
    {:ok, finished, _} = live(conn, "/base")
    assert has_element?(finished, "#base-rank-7[aria-current=step]")
    assert has_element?(finished, "#base-ascent-complete")
    assert has_element?(finished, "#pve-progression footer #base-collection img.avatar")
    refute has_element?(finished, "#base-rank-progress, #base-rewards-btn, #base-rank-8")
  end

  describe "rewards modal" do
    test "renders the progression rewards modal and trigger", %{conn: conn} do
      hero = create_base_hero()
      conn = conn |> log_in_user(hero.player.user) |> put_session(:player_id, hero.player_id)

      {:ok, view, html} = live(conn, "/base")

      assert html =~ "pve-tier-rewards"
      assert has_element?(view, "#base-rewards-btn[data-target='#pve-tier-rewards']")
      assert has_element?(view, "button[data-target='#pve-tier-rewards']")
    end
  end

  describe "continue event" do
    test "redirects to v2 training", %{conn: conn} do
      hero = create_base_hero()
      conn = conn |> log_in_user(hero.player.user) |> put_session(:player_id, hero.player_id)

      {:ok, view, _html} = live(conn, "/base")

      assert {:error, {:live_redirect, %{to: "/training"}}} =
               view
               |> element("#visible-hero-#{hero.id} [phx-click=continue]")
               |> render_click()
    end
  end

  describe "archive event" do
    test "removes hero from the list", %{conn: conn} do
      hero = create_base_hero()
      conn = conn |> log_in_user(hero.player.user) |> put_session(:player_id, hero.player_id)

      {:ok, view, _html} = live(conn, "/base")

      view
      |> element("#visible-hero-#{hero.id} [phx-click=archive]")
      |> render_click()

      refute has_element?(view, "#visible-hero-#{hero.id}")
    end
  end
end
