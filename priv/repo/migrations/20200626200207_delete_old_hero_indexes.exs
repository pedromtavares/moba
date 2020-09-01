defmodule Moba.Repo.Migrations.DeleteOldHeroIndexes do
  use Ecto.Migration

  def change do
    drop_if_exists index(:heroes, [:avatar_id])
    drop_if_exists index(:heroes, [:league_id])
  end
end
