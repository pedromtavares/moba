defmodule Moba.Repo.Migrations.AddIsBotToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :is_bot, :boolean, default: false
    end
  end
end
