defmodule Moba.Repo.Migrations.AddExtraLeagueFields do
  use Ecto.Migration

  def change do
    alter table(:heroes) do
      add :pvp_league_attempts, :integer, default: 0
      add :pvp_league_successes, :integer, default: 0
    end
  end
end
