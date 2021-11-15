defmodule Moba.Repo.Migrations.AddHistoryCodesToQuestProgressions do
  use Ecto.Migration

  def change do
    alter table(:quest_progressions) do
      add :history_codes, {:array, :string}, default: [], null: false
    end

    create index(:quest_progressions, [:completed_at])
  end
end
