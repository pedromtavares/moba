defmodule MobaWeb.V2.BrowserTitleTest do
  use MobaWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Test.TeamHelper
  alias Moba.Game.{TeamRuns, TeamTraining, TrainingEncounters}

  test "game pages keep the same browser title without LiveView title updates", %{conn: conn} do
    {scope, player} = team_account()
    conn = conn |> log_in_user(scope.user) |> put_session(:player_id, player.id)
    record = team_run(scope, player)

    for path <- ["/new", "/new/solo", "/base", "/training", "/arena", "/community", "/library"] do
      response = conn |> get(path) |> html_response(200) |> LazyHTML.from_document()
      assert LazyHTML.text(LazyHTML.query(response, "title")) == "Browser MOBA - Free PvP Auto-Battler"
      {:ok, view, _} = live(conn, path)
      assert page_title(view) == "Browser MOBA - Free PvP Auto-Battler"
    end

    {:ok, record} = TeamRuns.update(scope, record, &TeamTraining.battle(&1, hd(&1.targets[1]).id))
    encounter = TeamTraining.active_encounter(TeamRuns.state(record))
    {:ok, battle, _} = live(conn, TrainingEncounters.path(encounter, 1))
    assert page_title(battle) == "Browser MOBA - Free PvP Auto-Battler"

    {:ok, record} = TeamRuns.update(scope, record, &%{&1 | phase: :finished})
    {:ok, profile, _} = live(conn, "/teams/#{record.id}")
    assert page_title(profile) == "Browser MOBA - Free PvP Auto-Battler"
  end
end
