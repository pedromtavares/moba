defmodule Moba.Repo.Migrations.StoreForgedPairsOnHeroItems do
  use Ecto.Migration

  def change do
    alter table(:heroes_items) do
      add :forged_into_id, references(:heroes_items, on_delete: :nilify_all)
    end

    create unique_index(:heroes_items, [:forged_into_id], where: "forged_into_id IS NOT NULL")
  end
end
