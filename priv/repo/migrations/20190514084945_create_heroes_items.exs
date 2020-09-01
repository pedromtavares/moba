defmodule Moba.Repo.Migrations.CreateHeroesItems do
  use Ecto.Migration

  def change do
    create table(:heroes_items) do
      add :hero_id, references(:heroes, on_delete: :delete_all), null: false
      add :item_id, references(:items, on_delete: :delete_all), null: false
      timestamps()
    end
  end
end
