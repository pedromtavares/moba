defmodule Moba.Game.TrainingEncounters do
  @moduledoc "Persists team training as standalone Battles or Matches containing Battles."
  import Ecto.Query
  alias Moba.Repo
  alias Moba.Engine.Schema.{Battle, Turn}
  alias Moba.Game.TeamRuns
  alias Moba.Game.Training.Snapshot
  alias Moba.Game.Schema.{Match, TeamEncounter}

  def persist!(record, encounter) do
    encounter = Map.put(encounter, :id, record.id)
    team = Repo.get!(Moba.Game.Schema.TrainingTeam, record.team_run_id)
    multi = encounter.kind != :farm

    match =
      if multi do
        (Repo.get_by(Match, training_encounter_id: record.id) ||
           %Match{training_team_id: team.id, training_encounter_id: record.id, player_id: team.player_id})
        |> Ecto.Changeset.change(%{
          type: "training",
          team_size: length(encounter.radiant),
          phase: if(encounter.status == :finished, do: "finished", else: "started"),
          phase_changed_at: DateTime.utc_now() |> DateTime.truncate(:second),
          player_picks: [],
          opponent_picks: [],
          generated_picks: [],
          training_state: Snapshot.encode(encounter),
          winner_id: if(encounter.winner == :radiant, do: team.player_id)
        })
        |> Repo.insert_or_update!()
      end

    battles =
      encounter.battles
      |> Enum.with_index(1)
      |> Enum.map(fn {snapshot, index} ->
        battle =
          Repo.get_by(Battle, training_encounter_id: record.id, training_index: index) ||
            %Battle{
              training_team_id: team.id,
              training_encounter_id: record.id,
              training_index: index,
              attacker_player_id: team.player_id
            }

        battle =
          battle
          |> Ecto.Changeset.change(%{
            type: "training",
            match_id: match && match.id,
            finished: snapshot.finished || false,
            winner_player_id: if(player_won?(snapshot), do: team.player_id),
            training_state: Snapshot.encode(if(multi, do: %{snapshot | turns: []}, else: encounter))
          })
          |> Repo.insert_or_update!()

        saved = Repo.aggregate(from(t in Turn, where: t.battle_id == ^battle.id), :max, :number) || 0

        for turn <- snapshot.turns, turn.number > saved do
          %Turn{}
          |> Ecto.Changeset.change(
            battle_id: battle.id,
            number: turn.number,
            skill_code: turn.skill_code,
            item_code: turn.item_code
          )
          |> Ecto.Changeset.put_embed(:attacker, turn.attacker)
          |> Ecto.Changeset.put_embed(:defender, turn.defender)
          |> Repo.insert!()
        end

        battle
      end)

    encounter = Map.merge(encounter, %{match_id: match && match.id, battle_ids: Enum.map(battles, & &1.id)})
    source = match || hd(battles)
    source |> Ecto.Changeset.change(training_state: Snapshot.encode(encounter)) |> Repo.update!()
    encounter
  end

  def load(%TeamEncounter{} = record) do
    source =
      Repo.get_by(Match, training_encounter_id: record.id) ||
        Repo.get_by(Battle, training_encounter_id: record.id, training_index: 1)

    %{record | state: source && source.training_state}
  end

  def replay(%TeamEncounter{state: nil} = record), do: record |> load() |> read_replay()
  def replay(%TeamEncounter{} = record), do: read_replay(record)

  defp read_replay(record) do
    with {:ok,
          %{id: id, match_id: match_id, battle_ids: [_ | _], battles: [_ | _], kind: kind, status: status} = replay} <-
           Snapshot.read(record.state),
         true <- id == record.id,
         true <- kind in [:farm, :league, :boss] and status in [:pending, :finished],
         true <- is_nil(match_id) or is_integer(match_id),
         true <- length(replay.battle_ids) == length(replay.battles),
         true <- Enum.all?(replay.battle_ids, &is_integer/1),
         true <- Enum.all?(replay.battles, &match?(%Battle{turns: turns} when is_list(turns), &1)) do
      {:ok, replay}
    else
      _ -> {:error, :invalid_snapshot}
    end
  end

  def ready?(%TeamEncounter{} = record, encounter) do
    with {:ok, replay} <- replay(record),
         true <- replay.match_id == encounter[:match_id] and replay.battle_ids == encounter[:battle_ids] do
      battles =
        from b in Battle, where: b.training_encounter_id == ^record.id, order_by: b.training_index, select: b.id

      battles =
        if replay.match_id,
          do: from(b in battles, where: b.match_id == ^replay.match_id),
          else: from(b in battles, where: is_nil(b.match_id))

      Repo.all(battles) == replay.battle_ids
    else
      _ -> false
    end
  end

  def for_battle!(scope, id) do
    battle = Repo.get!(Battle, id)
    if is_nil(battle.training_team_id), do: raise(Ecto.NoResultsError, queryable: Battle)

    %{
      record: TeamRuns.encounter!(scope, battle.training_team_id, battle.training_encounter_id),
      index: battle.training_index
    }
  end

  def for_match!(scope, id) do
    match = Repo.get!(Match, id)
    if is_nil(match.training_team_id), do: raise(Ecto.NoResultsError, queryable: Match)
    %{record: TeamRuns.encounter!(scope, match.training_team_id, match.training_encounter_id), index: nil}
  end

  def path(encounter, index \\ nil)

  def path(%{battle_ids: _} = encounter, index) do
    cond do
      index -> "/battles/#{Enum.fetch!(encounter.battle_ids, index - 1)}"
      encounter.match_id -> "/matches/#{encounter.match_id}"
      true -> "/battles/#{hd(encounter.battle_ids)}"
    end
  end

  def hydrate(%Battle{training_state: state} = record) do
    with {:ok, snapshot} <- Snapshot.read(state),
         %Battle{} = snapshot <- battle_snapshot(snapshot, record.training_index) do
      %{
        snapshot
        | id: record.id,
          match_id: record.match_id,
          training_team_id: record.training_team_id,
          training_encounter_id: record.training_encounter_id,
          training_index: record.training_index,
          inserted_at: record.inserted_at,
          finished: record.finished,
          turns: record.turns
      }
    else
      _ -> record
    end
  end

  defp battle_snapshot(%{battles: battles}, index) when is_list(battles) and is_integer(index) and index > 0,
    do: Enum.at(battles, index - 1)

  defp battle_snapshot(snapshot, _), do: snapshot

  defp player_won?(%{winner: %{player: %{id: -1}}}), do: true
  defp player_won?(_), do: false
end
