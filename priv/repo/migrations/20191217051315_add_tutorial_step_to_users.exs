defmodule Moba.Repo.Migrations.AddTutorialStepToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :tutorial_step, :integer, default: 1
    end
  end
end
