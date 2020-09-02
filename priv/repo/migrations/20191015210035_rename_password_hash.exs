defmodule Moba.Repo.Migrations.RenamePasswordHash do
  use Ecto.Migration

  def change do
    rename table(:users), :encrypted_password, to: :password_hash
  end
end
