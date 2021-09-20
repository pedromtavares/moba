defmodule Moba.Repo.Migrations.CreateDuels do
  use Ecto.Migration

  def change do
    create table(:duels) do
      add :user_id, references(:users, on_delete: :delete_all)
      add :opponent_id, references(:users, on_delete: :delete_all)
      add :winner_id, references(:users)

      add :user_first_pick_id, references(:heroes, on_delete: :delete_all)
      add :opponent_first_pick_id, references(:heroes, on_delete: :delete_all)

      add :user_second_pick_id, references(:heroes, on_delete: :delete_all)
      add :opponent_second_pick_id, references(:heroes, on_delete: :delete_all)

      add :phase, :string
      add :rewards, :map

      timestamps()
    end

    alter table(:battles) do
      add :duel_id, references(:duels, on_delete: :delete_all)
    end

    rename table(:users), :pvp_score, to: :duel_score
    rename table(:users), :pvp_wins, to: :duel_wins
    rename table(:users), :pvp_losses, to: :duel_count

    alter table(:users) do
      remove :pvp_points
    end
  end
end
