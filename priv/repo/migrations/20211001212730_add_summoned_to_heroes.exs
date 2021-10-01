defmodule Moba.Repo.Migrations.AddSummonedToHeroes do
  use Ecto.Migration

  def change do
    alter table(:heroes) do
      add :summoned, :boolean, default: false
    end
  end
end
