defmodule Moba.Engine.Schema.Battler do
  @moduledoc """
  Battler embedded schema that gets stored in every Turn
  All of these properties are manipulated by Effects
  """

  use Ecto.Schema

  @derive Jason.Encoder

  @primary_key false
  embedded_schema do
    field :hero_id, :integer
    field :name, :string
    field :code, :string
    field :image, Moba.Image.Type
    field :is_bot, :boolean

    field :level, :integer
    field :speed, :integer

    field :base_atk, :integer
    field :base_armor, :integer
    field :base_power, :integer
    field :atk, :integer
    field :power, :integer
    field :armor, :integer

    field :total_hp, :integer
    field :total_mp, :integer
    field :current_hp, :integer
    field :current_mp, :integer

    field :damage_type, :string

    field :battle_power, :integer, default: 0
    field :turn_power, :integer, default: 0
    field :purged_power, :integer, default: 0
    field :next_power, :integer, default: 0

    field :turn_power_normal, :integer, default: 0
    field :next_power_normal, :integer, default: 0
    field :battle_power_normal, :integer, default: 0

    field :turn_power_magic, :integer, default: 0
    field :next_power_magic, :integer, default: 0
    field :battle_power_magic, :integer, default: 0

    field :battle_armor, :integer, default: 0
    field :turn_armor, :integer, default: 0
    field :next_armor, :integer, default: 0

    field :turn_atk, :integer, default: 0

    field :total_buff, :float, default: 0.0
    field :total_reduction, :float, default: 0.0

    field :last_damage_taken, :integer, default: 0
    field :last_damage_caused, :integer, default: 0
    field :damage, :integer, default: 0
    field :self_damage, :integer, default: 0

    field :hp_regen, :integer, default: 0
    field :last_hp, :integer, default: 0

    field :mp_regen, :integer, default: 0
    field :mp_burn, :integer, default: 0

    field :spell_count, :integer, default: 0

    field :double_skill, :map, virtual: true
    field :double_skill_code, :string
    field :delayed_skill, :map, virtual: true
    field :delayed_skill_code, :string
    field :permanent_skill, :map, virtual: true
    field :permanent_skill_code, :string
    field :last_skill, :map, virtual: true
    field :last_skill_code, :string

    field :buffs, {:array, :map}, default: []
    field :debuffs, {:array, :map}, default: []
    field :defender_buffs, {:array, :map}, default: []
    field :attacker_debuffs, {:array, :map}, default: []

    field :null_armor, :boolean, default: false
    field :stunned, :boolean, default: false
    field :silenced, :boolean, default: false
    field :physically_invulnerable, :boolean, default: false
    field :invulnerable, :boolean, default: false
    field :immortal, :boolean, default: false
    field :inneffectable, :boolean, default: false
    field :miss, :boolean, default: false
    field :disarmed, :boolean, default: false
    field :undisarmable, :boolean, default: false
    field :executed, :boolean, default: false
    field :charging, :boolean, default: false
    field :extra, :boolean, default: false
    field :bonus, :string

    field :active_skills, {:array, :map}, default: [], virtual: true
    field :passive_skills, {:array, :map}, default: [], virtual: true
    field :active_items, {:array, :map}, default: [], virtual: true
    field :passive_items, {:array, :map}, default: [], virtual: true
    field :skill_order, {:array, :map}, default: [], virtual: true
    field :item_order, {:array, :map}, default: [], virtual: true

    field :effects, {:array, :map}, default: []
    field :cooldowns, :map, default: %{}
    field :future_cooldowns, :map, default: %{}
  end
end
