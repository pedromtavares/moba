defmodule Moba.Repo.Migrations.AddUnreadIdIndex do
  use Ecto.Migration

  def change do
    create index(:battles, [:unread_id])
  end
end
