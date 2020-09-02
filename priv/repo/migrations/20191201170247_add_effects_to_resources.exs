defmodule Moba.Repo.Migrations.AddEffectsToResources do
  use Ecto.Migration

  def change do
    alter table(:skills) do
      add :effects, :text
    end

    alter table(:items) do
      add :effects, :text
    end
  end
end
