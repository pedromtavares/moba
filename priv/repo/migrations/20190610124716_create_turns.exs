defmodule Moba.Repo.Migrations.CreateTurns do
  use Ecto.Migration

  def change do
    create table(:turns) do
      add :battle_id, references(:battles, on_delete: :delete_all)
      add :previous_turn_id, references(:turns, on_delete: :nothing)

      add :number, :integer

      add :item, :map
      add :skill, :map

      add :attacker, :map
      add :defender, :map

      timestamps()
    end

    create index(:turns, [:battle_id])
  end
end
