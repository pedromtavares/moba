defmodule Moba.Repo.Migrations.AddArchivedAtToHeroes do
  use Ecto.Migration

  def change do
    alter table(:heroes) do
      add :archived_at, :utc_datetime
    end
  end
end
