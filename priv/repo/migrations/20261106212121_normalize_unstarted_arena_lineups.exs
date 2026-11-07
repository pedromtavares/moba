defmodule Moba.Repo.Migrations.NormalizeUnstartedArenaLineups do
  use Ecto.Migration

  def up do
    # Only selections that have never started change size. Played matches retain every battle and pick.
    execute """
    UPDATE matches SET team_size = 3,
      player_picks = CASE WHEN jsonb_array_length(player_picks) > 3
        THEN jsonb_build_array(player_picks -> 0, player_picks -> 1, player_picks -> 2)
        ELSE player_picks END,
      opponent_picks = CASE WHEN jsonb_array_length(opponent_picks) > 3
        THEN jsonb_build_array(opponent_picks -> 0, opponent_picks -> 1, opponent_picks -> 2)
        ELSE opponent_picks END
    WHERE phase IS NULL AND winner_id IS NULL AND type = 'manual' AND training_team_id IS NULL
      AND NOT EXISTS (SELECT 1 FROM battles WHERE battles.match_id = matches.id)
    """
  end

  def down, do: :ok
end
