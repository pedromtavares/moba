defmodule Moba.Repo.Migrations.AddUnlockFieldsToResources do
  use Ecto.Migration

  def change do
    rename table(:avatars), :prize_tier, to: :level_requirement

    alter table(:skills) do
      add :level_requirement, :integer
    end
  end
end
