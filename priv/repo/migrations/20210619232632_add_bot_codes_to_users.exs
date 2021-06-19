defmodule Moba.Repo.Migrations.AddBotCodesToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :bot_codes, {:array, :string}, default: []
    end
  end
end
