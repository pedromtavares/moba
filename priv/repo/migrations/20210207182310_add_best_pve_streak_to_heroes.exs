defmodule Moba.Repo.Migrations.AddBestPveStreakToHeroes do
  use Ecto.Migration

  def change do
    alter table(:heroes) do
      add :best_pve_streak, :integer, default: 0
    end
  end
end
