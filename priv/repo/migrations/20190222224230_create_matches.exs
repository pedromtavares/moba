defmodule Moba.Repo.Migrations.CreateMatches do
  use Ecto.Migration

  def change do
    create table(:matches) do
      add :active, :boolean, default: false, null: false
      add :last_battles_available_update_at, :utc_datetime

      timestamps()
    end
  end
end
