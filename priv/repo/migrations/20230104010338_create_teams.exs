defmodule Moba.Repo.Migrations.CreateTeams do
  use Ecto.Migration

  def change do
    create table(:teams) do
      add :name, :string
      add :pick_ids, :jsonb, default: "[]"
      add :defensive, :boolean, default: false
      add :used_count, :integer, default: 0
      add :player_id, references(:players)

      timestamps()
    end

    create index(:teams, [:player_id])
  end
end
