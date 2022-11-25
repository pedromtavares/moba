defmodule Moba.Repo.Migrations.AddImmortalStreaks do
  use Ecto.Migration

  def change do
    alter table(:players) do
      add :current_immortal_streak, :integer, default: 0
      add :best_immortal_streak, :integer, default: 0
      add :season_ranking, :integer
    end
  end
end
