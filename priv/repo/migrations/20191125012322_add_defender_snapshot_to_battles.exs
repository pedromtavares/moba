defmodule Moba.Repo.Migrations.AddDefenderSnapshotToBattles do
  use Ecto.Migration

  def change do
    alter table(:battles) do
      add :defender_snapshot, :map, default: %{}
    end
  end
end
