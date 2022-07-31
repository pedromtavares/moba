defmodule Moba.Repo.Migrations.RemoveResourcesFromTurns do
  use Ecto.Migration

  def change do
    alter table(:turns) do
      remove :skill
      remove :item
    end

    create index(:users, [:inserted_at])

    alter table(:battles) do
      remove :unread_id
    end
  end
end
