defmodule Moba.Repo.Migrations.AddBaseDamageToSkills do
  use Ecto.Migration

  def change do
    alter table(:skills) do
      add :base_damage, :integer
    end
  end
end
