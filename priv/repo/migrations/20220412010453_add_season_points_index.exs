defmodule Moba.Repo.Migrations.AddSeasonPointsIndex do
  use Ecto.Migration

  def change do
    create index(:users, [:season_points])
    drop index(:users, [:current_pvp_hero_id])
    drop index(:users, [:level])
  end
end
