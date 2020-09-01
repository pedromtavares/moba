defmodule Moba.Repo.Migrations.AddPvpActiveIndex do
  use Ecto.Migration

  def change do
    create index(:heroes, [:pvp_active])
  end
end
