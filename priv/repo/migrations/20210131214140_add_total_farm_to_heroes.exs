defmodule Moba.Repo.Migrations.AddTotalFarmToHeroes do
  use Ecto.Migration

  def change do
    alter table(:heroes) do
      add :total_farm, :integer, default: 0
    end
  end
end
