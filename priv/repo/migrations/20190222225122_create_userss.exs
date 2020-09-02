defmodule Moba.Repo.Migrations.CreateUserss do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :username, :string
      add :email, :string
      add :encrypted_password, :string

      add :level, :integer, default: 1
      add :experience, :integer, default: 0

      timestamps()
    end

    # create unique_index(:users, [:username])
    create unique_index(:users, [:email])
  end
end
