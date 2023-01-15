defmodule Moba.Repo.Migrations.AddDiscordToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :discord, :map, default: %{}
    end
  end
end
