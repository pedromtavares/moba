defmodule Moba.Repo.Migrations.CreateLeagues do
  use Ecto.Migration

  def change do
    create table(:leagues) do
      add :name, :string
      add :tier, :integer

      add :match_id, references(:matches, on_delete: :delete_all)

      timestamps()
    end

    create index(:leagues, [:match_id])

    alter table(:heroes) do
      add :league_id, references(:leagues)
    end

    create index(:heroes, [:league_id])
  end
end
