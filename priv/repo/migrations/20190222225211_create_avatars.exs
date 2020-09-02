defmodule Moba.Repo.Migrations.CreateAvatars do
  use Ecto.Migration

  def change do
    create table(:avatars) do
      add :name, :string
      add :code, :string
      add :role, :string
      add :image, :string
      add :atk, :integer
      add :total_hp, :integer
      add :total_mp, :integer
      add :atk_per_level, :integer
      add :hp_per_level, :integer
      add :mp_per_level, :integer
      add :speed, :integer
      add :armor, :integer
      add :power, :integer
      add :ultimate_code, :string

      add :ultimate_id, references(:skills, on_delete: :nothing), null: false
      add :match_id, references(:matches, on_delete: :delete_all)

      timestamps()
    end

    create index(:avatars, [:ultimate_id])
    create index(:avatars, [:match_id])
  end
end
