defmodule Moba.Repo.Migrations.MoreDuelIndexes do
  use Ecto.Migration

  def change do
    create index(:battles, [:duel_id])
  end
end
