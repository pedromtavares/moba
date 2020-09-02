defmodule Moba.Repo.Migrations.AddForeignKeyIndexesToHeroes do
  use Ecto.Migration

  def change do
    drop_if_exists index(:heroes, [:level])
    create index(:heroes, [:level, :bot_difficulty])
    create index(:heroes, [:active_build_id])
    create index(:heroes, [:avatar_id])
  end
end
