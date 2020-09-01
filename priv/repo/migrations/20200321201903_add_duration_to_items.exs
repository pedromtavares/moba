defmodule Moba.Repo.Migrations.AddDurationToItems do
  use Ecto.Migration

  def change do
    alter table(:items) do
      add :duration, :integer
    end
  end
end
