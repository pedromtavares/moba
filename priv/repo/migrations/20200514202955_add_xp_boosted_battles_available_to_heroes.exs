defmodule Moba.Repo.Migrations.AddXpBoostedBattlesAvailableToHeroes do
  use Ecto.Migration

  def change do
    alter table(:heroes) do
      add :xp_boosted_battles_available, :integer, default: 0
    end
  end
end
