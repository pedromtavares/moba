defmodule Moba.Repo.Migrations.AddFinishedAtToHeroes do
  use Ecto.Migration

  def change do
    alter table(:heroes) do
      add :finished_at, :utc_datetime
    end
  end
end
