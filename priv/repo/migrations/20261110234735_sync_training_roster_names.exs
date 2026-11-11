defmodule Moba.Repo.Migrations.SyncTrainingRosterNames do
  use Ecto.Migration

  def up do
    execute """
    UPDATE training_teams AS team
    SET name = users.username
    FROM players
    JOIN users ON users.id = players.user_id
    WHERE team.player_id = players.id AND team.name IS NULL
    """

    execute """
    UPDATE heroes AS hero
    SET name = team.name
    FROM training_teams AS team
    WHERE hero.training_team_id = team.id
      AND team.name IS NOT NULL
      AND hero.name IS DISTINCT FROM team.name
    """
  end

  def down, do: :ok
end
