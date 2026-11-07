defmodule Moba.Repo.Migrations.IndexRecentArenaMatchResults do
  use Ecto.Migration

  def change do
    create index(:matches, [:player_id, :updated_at, :id],
             name: :matches_recent_arena_results_index,
             where:
               "team_size = 3 AND phase = 'scored' AND training_team_id IS NULL AND winner_id IS NOT NULL"
           )
  end
end
