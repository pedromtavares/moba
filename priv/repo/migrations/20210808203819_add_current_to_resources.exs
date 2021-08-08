defmodule Moba.Repo.Migrations.AddCurrentToResources do
  use Ecto.Migration

  def change do
    alter table(:skills) do
      add :current, :boolean, default: false
    end
    alter table(:items) do
      add :current, :boolean, default: false
    end
    alter table(:avatars) do
      add :current, :boolean, default: false
    end

    create index(:skills, [:current])
    create index(:items, [:current])
    create index(:avatars, [:current])
  end
end
