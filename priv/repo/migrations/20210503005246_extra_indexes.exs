defmodule Moba.Repo.Migrations.ExtraIndexes do
  use Ecto.Migration

  def change do
    create index(:users, [:is_guest])
    create index(:users, [:is_bot])
    create index(:users, [:ranking])
    create index(:users, [:level])
  end
end
