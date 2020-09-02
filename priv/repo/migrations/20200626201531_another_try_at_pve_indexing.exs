defmodule Moba.Repo.Migrations.AnotherTryAtPveIndexing do
  use Ecto.Migration

  def change do
    drop_if_exists index(:heroes, [:level, :bot_difficulty])
    create index(:heroes, [:level])
  end
end
