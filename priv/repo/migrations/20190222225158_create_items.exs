defmodule Moba.Repo.Migrations.CreateItems do
  use Ecto.Migration

  def change do
    create table(:items) do
      add :name, :string
      add :code, :string
      add :image, :string
      add :description, :string
      add :rarity, :string
      add :active, :boolean, default: false
      add :mp_cost, :integer, default: 0
      add :cooldown, :integer, default: 0

      add :base_hp, :integer, default: 0
      add :base_mp, :integer, default: 0
      add :base_atk, :integer, default: 0
      add :base_power, :integer, default: 0
      add :base_armor, :integer, default: 0
      add :base_speed, :integer, default: 0

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

    create index(:items, [:match_id])
  end
end
