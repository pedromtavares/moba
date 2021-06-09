defmodule Moba.Repo.Migrations.AddDamageTypeToSkills do
  use Ecto.Migration

  def change do
    alter table(:skills) do
      add :damage_type, :string, default: "magic"
    end
  end
end
