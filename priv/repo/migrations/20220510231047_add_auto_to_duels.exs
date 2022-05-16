defmodule Moba.Repo.Migrations.AddAutoToDuels do
  use Ecto.Migration

  def change do
    alter table(:duels) do
      add :auto, :boolean, default: false
    end
  end
end
