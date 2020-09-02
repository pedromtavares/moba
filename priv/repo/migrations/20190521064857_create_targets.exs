defmodule Moba.Repo.Migrations.CreateTargets do
  use Ecto.Migration

  def change do
    create table(:targets) do
      add :difficulty, :string

      add :attacker_id, references(:heroes, on_delete: :delete_all), null: false
      add :defender_id, references(:heroes, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:targets, [:attacker_id])
    create index(:targets, [:defender_id])
  end
end
