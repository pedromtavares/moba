defmodule Moba.Repo.Migrations.CreateUnlocks do
  use Ecto.Migration

  def change do
    create table(:unlocks) do
      add :resource_code, :string
      add :user_id, references(:users, on_delete: :delete_all)

      timestamps()
    end

    create index(:unlocks, [:user_id])
  end
end
