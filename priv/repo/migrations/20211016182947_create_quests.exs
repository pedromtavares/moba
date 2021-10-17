defmodule Moba.Repo.Migrations.CreateQuests do
  use Ecto.Migration

  def change do
    create table(:quests) do
      add :title, :string
      add :description, :text
      add :shard_prize, :integer
      add :level, :integer, default: 1
      add :icon, :string
      add :code, :string
      add :initial_value, :integer, default: 0
      add :final_value, :integer
      add :daily, :boolean, default: false

      timestamps()
    end

    create table(:quest_progressions) do
      add :user_id, references(:users, on_delete: :delete_all)
      add :quest_id, references(:quests, on_delete: :delete_all)
      add :current_value, :integer, default: 0
      add :completed_at, :utc_datetime

      timestamps()
    end

    create index(:quest_progressions, [:user_id, :quest_id], unique: true)
  end
end
