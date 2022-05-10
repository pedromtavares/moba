defmodule Moba.Repo.Migrations.RemoveOldHeroFields do
  use Ecto.Migration

  def change do
    alter table(:heroes) do
      remove :easy_mode, :boolean
      remove :pve_points, :integer
      remove :buffed_battles_available, :integer
      remove :xp_boosted_battles_available, :integer
      remove :summoned, :boolean
      remove :shards_reward, :integer
      remove :pvp_active, :boolean
      remove :pvp_wins, :integer
      remove :pvp_losses, :integer
      remove :pvp_points, :integer
      remove :pvp_battles_available, :integer
      remove :pvp_ranking, :integer
      remove :pvp_history, :map
    end
  end
end
