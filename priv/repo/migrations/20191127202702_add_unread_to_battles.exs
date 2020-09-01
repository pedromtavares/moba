defmodule Moba.Repo.Migrations.AddUnreadToBattles do
  use Ecto.Migration

  def change do
    alter table(:battles) do
      add :unread_id, :integer
    end
  end
end
