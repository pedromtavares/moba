defmodule Moba.Repo.Migrations.AddTypeToBattles do
  use Ecto.Migration

  def change do
    alter table(:battles) do
      add :type, :string
    end
  end
end
