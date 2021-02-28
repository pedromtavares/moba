defmodule Moba.Repo.Migrations.AddFinishedPveToHeroes do
  use Ecto.Migration

  def change do
    alter table(:heroes) do
      add :finished_pve, :boolean, default: false
    end

    create index(:heroes, [:finished_pve])
  end
end
