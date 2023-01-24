defmodule Moba.Repo.Migrations.AddPlayersToBattles do
  use Ecto.Migration

  def change do
    alter table(:battles) do
      add :attacker_player_id, references(:players)
      add :defender_player_id, references(:players)
      add :winner_player_id, references(:players)
      add :initiator_player_id, references(:players)
    end
  end
end
