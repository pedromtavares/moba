defmodule Moba.Repo.Migrations.RenameMatchUpdateField do
  use Ecto.Migration

  def change do
    rename table(:matches), :last_battles_available_update_at, to: :last_server_update_at

    alter table(:matches) do
      add :last_pvp_round_at, :utc_datetime
    end
  end
end
