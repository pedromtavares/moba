defmodule Moba.Repo.Migrations.AddExtraPvpFieldsToHeroes do
  use Ecto.Migration

  def change do
    alter table(:heroes) do
      add :pvp_ranking, :integer
      add :pvp_wins, :integer, default: 0
      add :pvp_losses, :integer, default: 0
      add :pvp_league_step, :integer
    end
  end
end
