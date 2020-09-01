defmodule Moba.Repo.Migrations.AddIsGuestToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :is_guest, :boolean, default: false
      add :last_online_at, :utc_datetime
    end
  end
end
