defmodule Moba.Repo.Migrations.AddIndexesForDuels do
  use Ecto.Migration

  def change do
    create index(:duels, [:user_id])
    create index(:duels, [:opponent_id])
    create index(:duels, [:winner_id])
    create index(:duels, [:user_first_pick_id])
    create index(:duels, [:user_second_pick_id])
    create index(:duels, [:opponent_first_pick_id])
    create index(:duels, [:opponent_second_pick_id])
  end
end
