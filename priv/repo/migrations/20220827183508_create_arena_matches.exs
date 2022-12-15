defmodule Moba.Repo.Migrations.CreateArenaMatches do
  use Ecto.Migration

  def change do
    create table(:matches) do
      add :player_id, references(:players), null: false, on_delete: :delete_all
      add :opponent_id, references(:players), null: false, on_delete: :delete_all
      add :winner_id, references(:players)

      add :player_picks, :jsonb, default: "[]"
      add :opponent_picks, :jsonb, default: "[]"
      add :generated_picks, :jsonb, default: "[]"

      add :type, :string
      add :phase, :string
      add :phase_changed_at, :utc_datetime
      add :rewards, :map

      timestamps()
    end

    create index(:matches, [:player_id])
    create index(:matches, [:opponent_id])
    create index(:matches, [:player_id, :opponent_id])

    alter table(:battles) do
      add :match_id, references(:matches, on_delete: :delete_all)
    end

    create index(:battles, [:match_id])
  end
end
