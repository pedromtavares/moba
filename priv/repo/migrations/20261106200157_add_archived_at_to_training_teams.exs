defmodule Moba.Repo.Migrations.AddArchivedAtToTrainingTeams do
  use Ecto.Migration

  def change do
    alter table(:training_teams) do
      add :archived_at, :utc_datetime
    end
  end
end
