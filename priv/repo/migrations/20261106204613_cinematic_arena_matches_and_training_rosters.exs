defmodule Moba.Repo.Migrations.CinematicArenaMatchesAndTrainingRosters do
  use Ecto.Migration

  def up do
    alter table(:matches) do
      add :interactive, :boolean, null: false, default: false
    end

    alter table(:battles) do
      add :attacker_initial_hp, :integer
      add :attacker_initial_mp, :integer
    end

    alter table(:teams) do
      add :training_team_id, references(:training_teams, on_delete: :nilify_all)
    end

    create unique_index(:teams, [:training_team_id])

    # Saved Arena lineups use three slots; historical Match records keep their original sizes.
    execute "UPDATE teams SET pick_ids = jsonb_path_query_array(pick_ids, '$[0 to 2]') WHERE jsonb_array_length(pick_ids) > 3"

    execute """
    INSERT INTO teams (name, player_id, training_team_id, pick_ids, defensive, used_count, inserted_at, updated_at)
    SELECT COALESCE(NULLIF(r.name, ''), u.username, 'Training team'), r.player_id, r.id, to_jsonb(r.hero_ids),
           false, 0, NOW(), NOW()
    FROM training_teams r
    JOIN players p ON p.id = r.player_id
    LEFT JOIN users u ON u.id = p.user_id
    WHERE r.finished_at IS NOT NULL AND r.archived_at IS NULL AND r.league_tier >= 3
      AND cardinality(r.hero_ids) = 3
      AND 3 = (SELECT count(*) FROM heroes h WHERE h.id = ANY(r.hero_ids)
               AND h.player_id = r.player_id AND h.archived_at IS NULL AND h.finished_at IS NOT NULL)
    ON CONFLICT (training_team_id) DO NOTHING
    """
  end

  def down do
    alter table(:battles) do
      remove :attacker_initial_hp
      remove :attacker_initial_mp
    end

    drop unique_index(:teams, [:training_team_id])
    alter table(:teams), do: remove(:training_team_id)
    alter table(:matches), do: remove(:interactive)
  end
end
