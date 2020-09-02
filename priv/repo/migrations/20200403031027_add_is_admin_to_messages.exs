defmodule Moba.Repo.Migrations.AddIsAdminToMessages do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add :is_admin, :boolean, default: false
    end
  end
end
