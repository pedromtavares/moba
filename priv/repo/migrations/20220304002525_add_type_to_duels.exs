defmodule Moba.Repo.Migrations.AddTypeToDuels do
  use Ecto.Migration

  def change do
    alter table(:duels) do
      add :type, :string
    end
  end
end
