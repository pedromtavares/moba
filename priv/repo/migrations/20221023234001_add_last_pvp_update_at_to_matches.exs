defmodule Moba.Repo.Migrations.AddLastPvpUpdateAtToMatches do
  use Ecto.Migration

  def change do
    alter table(:seasons) do
      add :last_pvp_update_at, :utc_datetime
    end
  end
end
