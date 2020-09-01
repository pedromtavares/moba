defmodule Moba.Repo.Migrations.AddEnabledToResources do
  use Ecto.Migration

  def change do
    alter table(:skills) do
      add :enabled, :boolean, default: true
    end

    alter table(:items) do
      add :enabled, :boolean, default: true
    end

    alter table(:avatars) do
      add :enabled, :boolean, default: true
    end
  end
end
