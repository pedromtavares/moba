defmodule Moba.Repo.Migrations.CreateHeroes do
  use Ecto.Migration

  def change do
    create table(:heroes) do
      add :name, :string
      add :experience, :integer, default: 0
      add :level, :integer, default: 1

      add :skill_levels_available, :integer, default: 0
      add :battles_available, :integer, default: 0

      add :win_streak, :integer, default: 0
      add :loss_streak, :integer, default: 0
      add :wins, :integer, default: 0
      add :losses, :integer, default: 0
      add :ties, :integer, default: 0

      add :total_hp, :integer, default: 10
      add :total_mp, :integer, default: 10
      add :atk, :integer, default: 1
      add :power, :integer, default: 0
      add :armor, :integer, default: 0
      add :speed, :integer, default: 0

      add :item_hp, :integer, default: 0
      add :item_mp, :integer, default: 0
      add :item_atk, :integer, default: 0
      add :item_power, :integer, default: 0
      add :item_armor, :integer, default: 0
      add :item_speed, :integer, default: 0

      add :bot_difficulty, :string
      add :gold, :integer, default: 0
      add :item_level, :integer, default: 0

      add :skill_order, {:array, :string}
      add :item_order, {:array, :string}

      add :match_id, references(:matches, on_delete: :delete_all)
      add :user_id, references(:users, on_delete: :delete_all)
      add :avatar_id, references(:avatars, on_delete: :nothing), null: false

      timestamps()
    end

    create index(:heroes, [:match_id])
    create index(:heroes, [:user_id])
    create index(:heroes, [:avatar_id])
  end
end
