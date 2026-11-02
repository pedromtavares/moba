defmodule Moba.Repo.Migrations.SnapshotBattleLoadoutsAndBindPlayersToSeasons do
  use Ecto.Migration

  def up do
    alter table(:battles) do
      add :loadouts, :map, default: %{}, null: false
    end

    # Preserve duplicate legacy records and their heroes. Bind only the most
    # progressed record per account to the active season; the existing unique
    # (user_id, season_id) index protects future inserts.
    execute """
    WITH active AS (SELECT id FROM seasons WHERE active = true ORDER BY id LIMIT 1),
    candidates AS (
      SELECT p.id, row_number() OVER (
        PARTITION BY p.user_id ORDER BY p.pve_tier DESC, p.pvp_points DESC, p.total_farm DESC, p.id
      ) AS position
      FROM players p WHERE p.season_id IS NULL AND p.user_id IS NOT NULL
        AND NOT EXISTS (
          SELECT 1 FROM players existing, active
          WHERE existing.user_id = p.user_id AND existing.season_id = active.id
        )
    )
    UPDATE players SET season_id = active.id FROM candidates, active
    WHERE players.id = candidates.id AND candidates.position = 1
    """

    execute """
    UPDATE players SET season_id = (SELECT id FROM seasons WHERE active = true ORDER BY id LIMIT 1)
    WHERE season_id IS NULL AND user_id IS NULL
    """
  end

  def down do
    alter table(:battles) do
      remove :loadouts
    end
  end
end
