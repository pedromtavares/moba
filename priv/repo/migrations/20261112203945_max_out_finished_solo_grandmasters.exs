defmodule Moba.Repo.Migrations.MaxOutFinishedSoloGrandmasters do
  use Ecto.Migration

  def up do
    execute """
    WITH grandmasters AS (
      SELECT id, avatar_id
      FROM heroes
      WHERE finished_at IS NOT NULL
        AND league_tier = 6
        AND training_team_id IS NULL
        AND bot_difficulty IS NULL
        AND player_id IS NOT NULL
    ), equipment AS (
      SELECT hi.hero_id,
             SUM(CASE i.rarity
                   WHEN 'normal' THEN 400
                   WHEN 'rare' THEN 1200
                   WHEN 'epic' THEN 2400
                   WHEN 'legendary' THEN 4800
                   ELSE 0
                 END + CASE WHEN hi.forged_into_id IS NOT NULL THEN 800 ELSE 0 END) AS gold
      FROM heroes_items hi
      JOIN grandmasters gm ON gm.id = hi.hero_id
      JOIN items i ON i.id = hi.item_id
      GROUP BY hi.hero_id
    )
    UPDATE heroes AS h
    SET level = GREATEST(h.level, 30),
        experience = CASE WHEN h.level < 30 THEN 0 ELSE h.experience END,
        atk = h.atk + GREATEST(30 - h.level, 0) * a.atk_per_level,
        total_hp = h.total_hp + GREATEST(30 - h.level, 0) * a.hp_per_level,
        total_mp = h.total_mp + GREATEST(30 - h.level, 0) * a.mp_per_level,
        skill_levels_available = h.skill_levels_available + GREATEST(14 - h.level / 2, 0),
        gold = GREATEST(h.gold, 32000 - COALESCE(equipment.gold, 0))
    FROM grandmasters gm
    JOIN avatars a ON a.id = gm.avatar_id
    LEFT JOIN equipment ON equipment.hero_id = gm.id
    WHERE h.id = gm.id
      AND (h.level < 30 OR h.gold < 32000 - COALESCE(equipment.gold, 0))
    """
  end

  # The original balances and levels cannot be reconstructed after the upgrade.
  def down, do: :ok
end
