defmodule Moba.Repo.Migrations.AddBotTierToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :bot_tier, :integer
    end
  end
end
