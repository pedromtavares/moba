defmodule Moba.Repo.Migrations.AddRefreshTargetsCountToHeroes do
  use Ecto.Migration

  def change do
    alter table(:heroes) do
      add :refresh_targets_count, :integer, default: 0
    end
  end
end
