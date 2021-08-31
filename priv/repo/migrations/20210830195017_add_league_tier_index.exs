defmodule Moba.Repo.Migrations.AddLeagueTierIndex do
  use Ecto.Migration

  def change do
    create index(:heroes, [:league_tier])
  end
end
