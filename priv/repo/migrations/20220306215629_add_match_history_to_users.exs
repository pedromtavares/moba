defmodule Moba.Repo.Migrations.AddMatchHistoryToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :match_history, :map, default: %{}
    end
  end
end
