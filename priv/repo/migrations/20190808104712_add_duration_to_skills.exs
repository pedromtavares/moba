defmodule Moba.Repo.Migrations.AddDurationToSkills do
  use Ecto.Migration

  def change do
    alter table(:skills) do
      add :duration, :integer
    end
  end
end
