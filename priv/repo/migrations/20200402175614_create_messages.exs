defmodule Moba.Repo.Migrations.CreateMessages do
  use Ecto.Migration

  def change do
    create table(:messages) do
      add :author, :string
      add :tier, :integer
      add :body, :string
      add :avatar_code, :string

      add :user_id, references(:users, on_delete: :delete_all)

      timestamps()
    end
  end
end
