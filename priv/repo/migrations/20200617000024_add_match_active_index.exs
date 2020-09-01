defmodule Moba.Repo.Migrations.AddMatchActiveIndex do
  use Ecto.Migration

  def change do
    create index(:matches, [:active])
  end
end
