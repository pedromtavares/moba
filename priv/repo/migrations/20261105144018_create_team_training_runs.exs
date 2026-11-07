defmodule Moba.Repo.Migrations.CreateTeamTrainingRuns do
  use Ecto.Migration

  def change do
    create table(:team_runs) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :player_id, references(:players, on_delete: :delete_all), null: false
      add :state, :binary, null: false
      add :phase, :string, null: false
      add :turn, :integer, null: false, default: 1
      add :lock_version, :integer, null: false, default: 1
      timestamps()
    end

    create index(:team_runs, [:user_id, :id])

    create unique_index(:team_runs, [:user_id, :player_id],
             where: "phase = 'draft'",
             name: :one_team_draft_per_player
           )

    create table(:team_encounters) do
      add :team_run_id, references(:team_runs, on_delete: :delete_all), null: false
      add :turn, :integer, null: false
      add :label, :string, null: false
      timestamps(updated_at: false)
    end

    create index(:team_encounters, [:team_run_id, :id])
  end
end
