defmodule Moba.Repo.Migrations.AddTitleQuestIdToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :title_quest_id, references(:quests, on_delete: :nilify_all)
    end
  end
end
