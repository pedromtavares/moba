defmodule Moba.Repo.Migrations.AddDailyMatchesToPlayers do
  use Ecto.Migration

  def change do
    alter table(:players) do
      add :daily_matches, :integer, default: 0
      add :daily_wins, :integer, default: 0
      add :total_matches, :integer, default: 0
      add :total_wins, :integer, default: 0
    end
  end
end
