defmodule Moba.Repo.Migrations.AddWinnersToMatches do
  use Ecto.Migration

  def change do
    alter table(:matches) do
      add :winners, :map, default: %{}
    end
  end
end
