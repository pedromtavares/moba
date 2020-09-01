defmodule Moba.Repo.Migrations.PveBotIndexes do
  use Ecto.Migration

  def change do
    create index(:heroes, [:level, :bot_difficulty])
  end
end
