defmodule Moba.Repo.Migrations.AddPvpHistoryToHeroes do
  use Ecto.Migration

  def change do
    alter table(:heroes) do
      add :pvp_history, :map, default: %{}
    end
  end
end
