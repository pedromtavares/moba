defmodule Moba.Repo.Migrations.AddCodesToTurns do
  use Ecto.Migration

  def change do
    alter table(:turns) do
      add :skill_code, :string
      add :item_code, :string
    end
  end
end
