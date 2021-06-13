defmodule Moba.Repo.Migrations.CreateArenaPicks do
  use Ecto.Migration

  def change do
    create table(:arena_picks) do
      add :points, :integer, default: 0
      add :ranking, :integer, default: 0
      add :wins, :integer, default: 0
      add :losses, :integer, default: 0

      add :hero_id, references(:heroes)
      add :user_id, references(:users, on_delete: :delete_all)
      add :match_id, references(:matches)

      timestamps()
    end

    create index(:arena_picks, [:user_id])
  end
end
