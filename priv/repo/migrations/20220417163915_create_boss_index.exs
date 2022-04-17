defmodule Moba.Repo.Migrations.CreateBossIndex do
  use Ecto.Migration

  def change do
    create index(:heroes, [:boss_id])

    drop table(:arena_picks)
  end
end
