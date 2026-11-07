defmodule Moba.Repo.Migrations.IntegratePublicTeamTraining do
  use Ecto.Migration

  def change do
    rename table(:team_runs), to: table(:training_teams)

    alter table(:training_teams) do
      modify :user_id, :bigint, null: true, from: {:bigint, null: false}
      add :finished_at, :utc_datetime
      add :total_farm, :integer
      add :duration_seconds, :integer
      add :league_tier, :integer
      add :hero_ids, {:array, :bigint}, null: false, default: []
    end

    create unique_index(:training_teams, [:player_id],
             where: "phase = 'draft'",
             name: :one_training_draft_per_player
           )

    create index(:training_teams, [:total_farm, :duration_seconds],
             where: "finished_at IS NOT NULL"
           )

    alter table(:heroes) do
      add :training_team_id, references(:training_teams, on_delete: :nilify_all)
    end

    create index(:heroes, [:training_team_id])

    alter table(:matches) do
      add :team_size, :integer, null: false, default: 5
    end

    alter table(:matches) do
      modify :team_size, :integer, default: 3, from: {:integer, default: 5}
    end

    execute "UPDATE teams SET pick_ids = jsonb_path_query_array(pick_ids, '$[0 to 2]') WHERE jsonb_array_length(pick_ids) > 3",
            "SELECT 1"
  end
end
