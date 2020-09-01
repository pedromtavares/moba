defmodule Moba.Repo.Migrations.CreateSkills do
  use Ecto.Migration

  def change do
    create table(:skills) do
      add :name, :string
      add :code, :string
      add :image, :string
      add :description, :string
      add :mp_cost, :integer
      add :cooldown, :integer
      add :ultimate, :boolean, default: false
      add :passive, :boolean, default: false
      add :level, :integer, default: 1

      add :base_amount, :integer

      add :atk_multiplier, :float
      add :other_atk_multiplier, :float
      add :atk_regen_multiplier, :float
      add :hp_multiplier, :float
      add :other_hp_multiplier, :float
      add :hp_regen_multiplier, :float
      add :mp_multiplier, :float
      add :other_mp_multiplier, :float
      add :mp_regen_multiplier, :float
      add :extra_multiplier, :float
      add :armor_amount, :integer
      add :power_amount, :integer
      add :roll_number, :integer
      add :extra_amount, :integer

      add :match_id, references(:matches, on_delete: :delete_all)

      timestamps()
    end

    create index(:skills, [:match_id])
  end
end
