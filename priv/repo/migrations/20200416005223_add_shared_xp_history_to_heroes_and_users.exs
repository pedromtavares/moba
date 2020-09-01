defmodule Moba.Repo.Migrations.AddSharedXpHistoryToHeroesAndUsers do
  use Ecto.Migration

  def change do
    alter table(:heroes) do
      add :shared_xp_history, :map, default: %{}
    end

    alter table(:users) do
      add :shared_xp_history, :map, default: %{}
    end
  end
end
