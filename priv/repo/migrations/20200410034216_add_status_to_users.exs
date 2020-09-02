defmodule Moba.Repo.Migrations.AddStatusToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :status, :string, default: "unavailable"
    end
  end
end
