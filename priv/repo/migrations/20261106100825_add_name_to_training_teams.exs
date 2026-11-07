defmodule Moba.Repo.Migrations.AddNameToTrainingTeams do
  use Ecto.Migration

  def change do
    alter table(:training_teams) do
      add :name, :string
    end
  end
end
