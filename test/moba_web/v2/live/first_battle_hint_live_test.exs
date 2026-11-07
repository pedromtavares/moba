defmodule MobaWeb.V2.FirstBattleHintLiveTest do
  use MobaWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Test.TeamHelper

  test "a new roster guides players through one completed target battle with each hero", %{conn: conn} do
    {scope, player} = team_account(0)
    record = team_run(scope, player)
    conn = conn |> log_in_user(scope.user) |> put_session(:player_id, player.id)

    for id <- [1, 2, 3] do
      current = Game.TeamRuns.get!(scope, record.id)

      {:ok, current} =
        Game.TeamRuns.update(scope, current, fn run ->
          run |> easy_target(id) |> Game.TeamTraining.select(run.selected)
        end)

      run = Game.TeamRuns.state(current)
      {:ok, view, _} = live(conn, "/training")

      assert has_element?(view, "#team-select-#{run.selected}[aria-selected=true]")
      assert has_element?(view, "#team-select-#{id}[data-battle-guide]")
      refute has_element?(view, ".team-hero-selector button:not(#team-select-#{id})[data-battle-guide]")
      assert has_element?(view, "#first-battle-hero-arrow-#{id}[aria-hidden=true]")

      first = hd(run.targets[id])
      assert has_element?(view, "#team-hero-panel-#{id} #first-battle-arrow-#{first.id}[aria-hidden=true]")
      refute has_element?(view, ".first-battle-arrow:not(#first-battle-arrow-#{first.id})")

      view |> element("#gank-#{first.id}") |> render_click()
      pending = Game.TeamRuns.get!(scope, record.id)
      assert %{recipient: ^id, status: :pending} = Game.TeamTraining.active_encounter(Game.TeamRuns.state(pending))
      {:ok, _} = Game.TeamRuns.update(scope, pending, &finish_team(&1, scope))
    end

    {:ok, returned, _} = live(conn, "/training")
    assert has_element?(returned, ".targets .battle-button")
    refute has_element?(returned, ".first-battle-arrow, .first-battle-hero-arrow, [phx-hook=TutorialStep]")
  end

  test "old tutorial states cannot open guides or force the solo Shop open", %{conn: conn} do
    hero = create_base_hero(%{gold: 800})
    conn = log_in_player(conn, player_id: hero.player_id)

    for step <- [1, 3, 7, 8, 20, 30, 31] do
      Game.update_tutorial_step!(hero.player, step)
      {:ok, training, _} = live(conn, "/training")
      refute has_element?(training, "[phx-hook=TutorialStep], .first-battle-arrow")
      assert has_element?(training, "#shop-modal.d-none")
      assert has_element?(training, ".farm-tabs #farm-tab-meditation")

      for path <- ["/base", "/arena"] do
        {:ok, page, _} = live(conn, path)
        refute has_element?(page, "[phx-hook=TutorialStep], .first-battle-arrow")
      end

      assert Game.get_player!(hero.player_id).tutorial_step == step
      assert Game.list_matches(hero.player) == []
    end
  end

  test "opening an existing roster fills missing targets and persists their battle IDs", %{conn: conn} do
    {scope, player} = team_account(0)
    record = team_run(scope, player)

    {:ok, record} =
      Game.TeamRuns.update(scope, record, fn run ->
        %{run | targets: Map.new(run.targets, fn {id, targets} -> {id, Enum.take(targets, 2)} end)}
      end)

    conn = conn |> log_in_user(scope.user) |> put_session(:player_id, player.id)
    {:ok, view, _} = live(conn, "/training")
    saved = record |> then(&Game.TeamRuns.get!(scope, &1.id)) |> Game.TeamRuns.state()

    for id <- saved.order do
      assert length(saved.targets[id]) == 3
      for target <- saved.targets[id], do: assert(has_element?(view, "#team-hero-panel-#{id} #gank-#{target.id}"))
    end
  end
end
