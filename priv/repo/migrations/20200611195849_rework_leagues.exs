defmodule Moba.Repo.Migrations.ReworkLeagues do
  use Ecto.Migration

  def change do
    alter table(:heroes) do
      add :league_tier, :integer, default: 0
    end

    rename table(:heroes), :pvp_league_step, to: :league_step
    rename table(:heroes), :pvp_league_attempts, to: :league_attempts
    rename table(:heroes), :pvp_league_successes, to: :league_successes
  end
end
