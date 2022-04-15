defmodule Moba.Repo.Migrations.AddPhaseChangedAtToDuels do
  use Ecto.Migration

  def change do
    alter table(:duels) do
      add :phase_changed_at, :utc_datetime
    end
  end
end
