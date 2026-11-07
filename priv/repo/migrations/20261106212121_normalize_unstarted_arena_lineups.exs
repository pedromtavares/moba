defmodule Moba.Repo.Migrations.NormalizeUnstartedArenaLineups do
  use Ecto.Migration

  def up do
    # Only selections that have never started change size. Played matches retain every battle and pick.
    execute """
    UPDATE matches SET team_size = 3,
      player_picks = jsonb_path_query_array(player_picks, '$[0 to 2]'),
      opponent_picks = jsonb_path_query_array(opponent_picks, '$[0 to 2]')
    WHERE phase IS NULL AND winner_id IS NULL AND type = 'manual' AND training_team_id IS NULL
      AND NOT EXISTS (SELECT 1 FROM battles WHERE battles.match_id = matches.id)
    """
  end

  def down, do: :ok
end
