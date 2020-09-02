defmodule Moba.Repo.Migrations.GlobalArena do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :pvp_points, :integer, default: 0
      add :pvp_score, :map, default: %{}
      add :pvp_wins, :integer, default: 0
      add :pvp_losses, :integer, default: 0

      add :current_pve_hero_id, references(:heroes)
      add :current_pvp_hero_id, references(:heroes)
    end

    create index(:users, [:current_pvp_hero_id])
    create index(:users, [:current_pve_hero_id])

    alter table(:heroes) do
      add :pvp_active, :boolean, default: false
    end
  end
end
