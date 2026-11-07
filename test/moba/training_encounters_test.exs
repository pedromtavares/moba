defmodule Moba.Game.TrainingEncountersTest do
  use Moba.DataCase, async: true
  import Test.TeamHelper
  alias Moba.{Engine, Repo}
  alias Moba.Game.{TeamRuns, TeamTraining, TrainingEncounters}
  alias Moba.Game.Schema.{Match, TeamEncounter}
  alias Moba.Engine.Schema.{Battle, Turn}

  setup do
    {scope, player} = team_account()
    %{scope: scope, player: player, record: team_run(scope, player)}
  end

  test "a target is one native Battle, with real turns and a stable canonical URL", %{scope: scope, record: record} do
    {:ok, record} =
      TeamRuns.update(scope, record, fn run ->
        run = easy_target(run)
        TeamTraining.battle(run, hd(run.targets[1]).id)
      end)

    encounter = TeamRuns.state(record) |> TeamTraining.active_encounter()
    assert encounter.match_id == nil
    assert [id] = encounter.battle_ids
    assert TrainingEncounters.path(encounter) == "/battles/#{id}"
    assert Repo.get!(TeamEncounter, encounter.id).state == nil
    battle = Repo.get!(Battle, id)
    assert battle.type == "training"
    assert battle.match_id == nil
    assert battle.training_team_id == record.id
    assert Repo.aggregate(from(m in Match, where: m.training_team_id == ^record.id), :count) == 0
    assert Engine.auto_finish_battle!(Engine.get_battle!(id)).finished == false

    {:ok, record} = TeamRuns.update(scope, record, &finish_team(&1, scope))
    finished = hd(TeamRuns.state(record).encounters)
    assert finished.battle_ids == [id]
    battle = Engine.get_battle!(id)
    assert battle.finished
    assert battle.attacker.avatar.name == hd(finished.radiant).hero.avatar.name
    assert length(battle.turns) == length(hd(finished.battles).turns)
    assert Repo.aggregate(from(t in Turn, where: t.battle_id == ^id), :count) == length(battle.turns)
  end

  test "a team challenge is a native Match containing its native Battles and never enters Arena", %{
    scope: scope,
    player: player,
    record: record
  } do
    {:ok, record} =
      TeamRuns.update(scope, record, fn run ->
        %{run | turns_left: 0} |> TeamTraining.league() |> simple_league()
      end)

    encounter = TeamTraining.active_encounter(TeamRuns.state(record))
    match = Game.get_match!(encounter.match_id)
    assert match.type == "training"
    assert match.training_team_id == record.id
    assert match.opponent_id == nil
    assert TrainingEncounters.path(encounter) == "/matches/#{match.id}"
    assert hd(Engine.list_match_battles(match.id)).id == hd(encounter.battle_ids)
    assert Game.Matches.pending_match(player) == nil
    assert Game.list_matches(player) == []
    assert Game.Matches.match_id_for_player(player) == nil
    assert Game.Arena.continue_match!(match) == match

    {:ok, record} = TeamRuns.update(scope, record, &finish_team(&1, scope))
    finished = hd(TeamRuns.state(record).encounters)
    assert finished.match_id == match.id
    assert Game.get_match!(match.id).phase == "finished"
    battles = Engine.list_match_battles(match.id)
    assert length(battles) == length(finished.battles)
    assert length(battles) > 1
    assert Enum.all?(battles, &(&1.match_id == match.id && &1.finished))
    assert Enum.map(battles, & &1.id) == finished.battle_ids
    assert TrainingEncounters.path(finished, 2) == "/battles/#{Enum.at(finished.battle_ids, 1)}"
    {:ok, _} = TeamRuns.update(scope, record, & &1)
    assert Enum.map(Engine.list_match_battles(match.id), & &1.id) == finished.battle_ids
  end

  test "history ignores metadata without a replay and keeps valid battles", %{scope: scope, record: record} do
    orphan = Repo.insert!(%TeamEncounter{team_run_id: record.id, turn: 1, label: "Old target"})
    assert TeamRuns.encounters(scope, record.id) == []

    {:ok, record} =
      TeamRuns.update(scope, record, fn run ->
        run = easy_target(run)
        TeamTraining.battle(run, hd(run.targets[1]).id)
      end)

    current = TeamTraining.active_encounter(TeamRuns.state(record))
    assert [replay] = TeamRuns.encounters(scope, record.id)
    assert replay.id == current.id
    assert replay.battle_ids == current.battle_ids
    assert Repo.get!(TeamEncounter, orphan.id)
    {other, _} = team_account()
    assert TeamRuns.encounters(other, record.id) == []
  end

  test "canonical training records keep ownership checks", %{scope: scope, record: record} do
    {:ok, record} =
      TeamRuns.update(scope, record, fn run ->
        %{run | turns_left: 0} |> TeamTraining.league()
      end)

    encounter = TeamTraining.active_encounter(TeamRuns.state(record))
    {other, _} = team_account()
    assert_raise Ecto.NoResultsError, fn -> TrainingEncounters.for_battle!(other, hd(encounter.battle_ids)) end
    assert_raise Ecto.NoResultsError, fn -> TrainingEncounters.for_match!(other, encounter.match_id) end
    assert TrainingEncounters.for_match!(scope, encounter.match_id).record.id == encounter.id
  end

  test "ordinary battles and PvP matches still require their participants", %{player: player} do
    battle =
      %Battle{type: "pve"}
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.check_constraint(:attacker_id, name: :battle_participants)

    assert {:error, changeset} = Repo.insert(battle, mode: :savepoint)
    assert changeset.errors[:attacker_id]

    match =
      %Match{type: "manual", player_id: player.id}
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.check_constraint(:opponent_id, name: :match_participants)

    assert {:error, changeset} = Repo.insert(match, mode: :savepoint)
    assert changeset.errors[:opponent_id]
  end
end
