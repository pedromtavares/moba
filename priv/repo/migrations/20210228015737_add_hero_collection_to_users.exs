defmodule Moba.Repo.Migrations.AddHeroCollectionToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :hero_collection, :jsonb, default: "[]"
    end
  end
end
