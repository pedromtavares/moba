defmodule Moba.Repo.Migrations.AddBattlePoints do
  use Ecto.Migration

  def change do
    rename table(:heroes), :battles_available, to: :pve_battles_available

    alter table(:heroes) do
      add :pvp_battles_available, :integer, default: 0
      add :pve_points, :integer, default: 0
      add :pvp_points, :integer, default: 0
    end
  end
end
