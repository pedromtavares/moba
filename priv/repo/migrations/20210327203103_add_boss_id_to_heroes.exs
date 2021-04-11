defmodule Moba.Repo.Migrations.AddBossIdToHeroes do
  use Ecto.Migration

  def change do
    alter table(:heroes) do
      add :boss_id, references(:heroes, on_delete: :delete_all)
    end
  end
end
