defmodule Moba.Repo.Migrations.AddPvpPickFields do
  use Ecto.Migration

  def change do
    alter table(:heroes) do
      add :pvp_picks, :integer, default: 0
      add :pvp_last_picked, :utc_datetime
    end
  end
end
