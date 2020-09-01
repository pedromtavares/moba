defmodule Moba.Repo.Migrations.AddBuffedBattlesAvailable do
  use Ecto.Migration

  def change do
    alter table(:heroes) do
      add :buffed_battles_available, :integer, default: 0
    end
  end
end
