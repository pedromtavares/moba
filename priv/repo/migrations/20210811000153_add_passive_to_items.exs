defmodule Moba.Repo.Migrations.AddPassiveToItems do
  use Ecto.Migration

  def change do
    alter table(:items) do
      add :passive, :boolean, default: false
    end
  end
end
