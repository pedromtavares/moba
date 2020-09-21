defmodule Moba.Repo.Migrations.AddPvpLastPickedIndex do
  use Ecto.Migration

  def change do
    create index(:heroes, [:pvp_last_picked])
  end
end
