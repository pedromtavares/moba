defmodule Moba.Repo.Migrations.CreateBuilds do
  use Ecto.Migration

  def change do
    create table(:builds) do
      add :hero_id, references(:heroes, on_delete: :delete_all)
      add :type, :string
      add :skill_order, {:array, :string}
      add :item_order, {:array, :string}

      timestamps()
    end

    create index(:builds, [:hero_id])

    create table(:builds_skills) do
      add :build_id, references(:builds, on_delete: :delete_all), null: false
      add :skill_id, references(:skills, on_delete: :delete_all), null: false
      timestamps()
    end

    create unique_index(:builds_skills, [:build_id, :skill_id])

    alter table(:heroes) do
      add :active_build_id, references(:builds)
    end
  end
end
