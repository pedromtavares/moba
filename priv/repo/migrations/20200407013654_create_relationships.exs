defmodule Moba.Repo.Migrations.CreateRelationships do
  use Ecto.Migration

  def change do
    create table(:relationships) do
      add :user_one_id, references(:users, on_delete: :delete_all), null: false
      add :user_two_id, references(:users, on_delete: :delete_all), null: false
      add :pending, :boolean

      timestamps()
    end

    create unique_index(:relationships, [:user_one_id, :user_two_id])
  end
end
