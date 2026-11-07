defmodule Moba.Repo.Migrations.IntegrateTrainingEncountersWithBattlesAndMatches do
  use Ecto.Migration

  def up do
    alter table(:matches) do
      modify :opponent_id, :bigint, null: true, from: {:bigint, null: false}
      add :training_team_id, references(:training_teams, on_delete: :delete_all)
      add :training_encounter_id, references(:team_encounters, on_delete: :delete_all)
      add :training_state, :binary
    end

    alter table(:battles) do
      modify :attacker_id, :bigint, null: true, from: {:bigint, null: false}
      modify :defender_id, :bigint, null: true, from: {:bigint, null: false}
      add :training_team_id, references(:training_teams, on_delete: :delete_all)
      add :training_encounter_id, references(:team_encounters, on_delete: :delete_all)
      add :training_index, :integer
      add :training_state, :binary
    end

    create unique_index(:matches, [:training_encounter_id])
    create unique_index(:battles, [:training_encounter_id, :training_index])
    create index(:matches, [:training_team_id])
    create index(:battles, [:training_team_id])

    # Drafted heroes are snapshots until collection. Preserve required participants
    # for every ordinary battle and PvP match.
    create constraint(:matches, :match_participants,
             check:
               "opponent_id IS NOT NULL OR (type = 'training' AND training_team_id IS NOT NULL AND training_state IS NOT NULL)"
           )

    create constraint(:battles, :battle_participants,
             check:
               "(attacker_id IS NOT NULL AND defender_id IS NOT NULL) OR (type = 'training' AND training_team_id IS NOT NULL AND training_state IS NOT NULL)"
           )
  end

  def down do
    execute "DELETE FROM battles WHERE training_team_id IS NOT NULL"
    execute "DELETE FROM matches WHERE training_team_id IS NOT NULL"

    drop constraint(:battles, :battle_participants)
    drop constraint(:matches, :match_participants)
    drop index(:matches, [:training_encounter_id])
    drop index(:battles, [:training_encounter_id, :training_index])
    drop index(:matches, [:training_team_id])
    drop index(:battles, [:training_team_id])

    alter table(:battles) do
      remove :training_state
      remove :training_index
      remove :training_encounter_id
      remove :training_team_id
      modify :attacker_id, :bigint, null: false
      modify :defender_id, :bigint, null: false
    end

    alter table(:matches) do
      remove :training_state
      remove :training_encounter_id
      remove :training_team_id
      modify :opponent_id, :bigint, null: false
    end
  end
end
