defmodule Moba.Repo.Migrations.CreateMoreHeroIndexes do
  use Ecto.Migration

  def change do
    create unique_index(:heroes_items, [:hero_id, :item_id])
  end
end
