defmodule Moba.Repo.Migrations.CreateBattles do
  use Ecto.Migration

  def change do
    create table(:battles) do
      add :match_id, references(:matches, on_delete: :delete_all)
      add :attacker_id, references(:heroes, on_delete: :delete_all), null: false
      add :defender_id, references(:heroes, on_delete: :delete_all), null: false
      add :winner_id, references(:heroes, on_delete: :nothing)
      add :initiator_id, references(:heroes, on_delete: :nothing)
      add :difficulty, :string
      add :rewards, :map
      add :finished, :boolean, default: false

      timestamps()
    end

    create index(:battles, [:match_id])
    create index(:battles, [:attacker_id])
    create index(:battles, [:defender_id])
  end
end
