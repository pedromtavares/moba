defmodule Moba.Repo.Migrations.AddPickPositionToBattles do
  use Ecto.Migration

  def change do
    alter table(:battles) do
      add :attacker_pick_position, :integer
      add :defender_pick_position, :integer
    end
  end
end
