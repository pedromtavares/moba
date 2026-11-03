defmodule Moba.Repo.Migrations.AddInventoryOrderToHeroes do
  use Ecto.Migration

  def change do
    alter table(:heroes) do
      add :inventory_order, {:array, :string}, default: [], null: false
    end
  end
end
