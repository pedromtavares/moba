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
      view |> element("#finished-heroes-btn") |> render_click()
      assert has_element?(view, "#hero-list-finished #visible-team-#{finished.id}")
      assert has_element?(view, "#base-team-continue-#{finished.id}[href='/teams/#{finished.id}']", "View team")
      refute has_element?(view, "#visible-team-#{active.id}")

      for id <- finished.hero_ids, do: refute(has_element?(view, "#visible-hero-#{id}"))

      view |> element("#in-progress-heroes-btn") |> render_click()
      view |> element("#visible-hero-#{solo.id} [phx-click=continue]") |> render_click()
      assert_redirect(view, "/training?solo=true")
    end

    test "load all includes older teams without including drafts or abandoned runs", %{conn: conn} do
      {scope, player} = team_account()
      oldest = team_run(scope, player)
      for _ <- 1..Moba.base_hero_count(), do: team_run(scope, player)
      abandoned = team_run(scope, player)
      {:ok, _} = Game.TeamRuns.update(scope, abandoned, &%{&1 | phase: :abandoned})
      {:ok, draft} = Game.TeamRuns.draft(scope, player)
      conn = conn |> log_in_user(scope.user) |> put_session(:player_id, player.id)
      {:ok, view, _} = live(conn, "/base")

      refute has_element?(view, "#visible-team-#{oldest.id}")
      view |> element("#load-all-heroes-unfinished") |> render_click()
      assert has_element?(view, "#visible-team-#{oldest.id}")
      refute has_element?(view, "#visible-team-#{abandoned.id}, #visible-team-#{draft.id}")
      refute has_element?(view, "#load-all-heroes-unfinished")
    end
  end

  describe "unauthenticated access" do
    test "redirects to /start without player_id in session", %{conn: conn} do
      conn = get(conn, "/base")
      assert redirected_to(conn) == "/start"
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
      assert html =~ "In Progress"
      assert html =~ "Finished"
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

      assert has_element?(view, "#finished-heroes-btn")
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

      render_click(view, "show-finished", %{})

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

      render_click(view, "show-finished", %{})
      render_click(view, "show-unfinished", %{})

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

      preview |> element("#finished-heroes-btn") |> render_click()
      assert has_element?(preview, "#active-finished-heroes-btn[aria-pressed=true]")
      assert has_element?(preview, "#visible-hero-#{finished.id}")
      refute has_element?(preview, "#visible-hero-#{hero.id}")

      preview |> element("#in-progress-heroes-btn") |> render_click()
      assert has_element?(preview, "#base-page.base-page #visible-hero-#{hero.id}")
      assert has_element?(preview, "#active-in-progress-heroes-btn[aria-pressed=true]")
    end
  end

  test "cinematic progression retains advanced requirements and the final rank", %{conn: conn} do
    player = create_player!(%{pve_tier: 4, pve_progression: %{master_codes: ["phantom_assassin"]}})
    hero = create_base_hero(%{}, player)
    conn = log_in_player(conn, player_id: hero.player_id)
    {:ok, view, _} = live(conn, "/base")

    assert has_element?(view, "#base-rank-4[aria-current=step]")
    assert has_element?(view, "#base-rank-5.is-next")
    assert has_element?(view, "#base-quest-description", "20 different Avatars")
    assert has_element?(view, "#base-rank-progress[aria-valuetext='1/20 Avatars'][aria-valuenow='5']")
    assert has_element?(view, "#base-rewards-btn[data-target='#pve-tier-rewards']")

    Game.update_player!(player, %{pve_tier: Moba.max_pve_tier()})
    {:ok, finished, _} = live(conn, "/base")
    assert has_element?(finished, "#base-rank-7[aria-current=step]")
    assert has_element?(finished, "#base-ascent-complete")
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
