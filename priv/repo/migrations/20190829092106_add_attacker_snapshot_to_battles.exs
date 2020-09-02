defmodule Moba.Repo.Migrations.AddAttackerSnapshotToBattles do
  use Ecto.Migration

  def change do
    alter table(:battles) do
      add :attacker_snapshot, :map, default: %{}
    end
  end
end
