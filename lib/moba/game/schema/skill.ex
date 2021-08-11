defmodule Moba.Game.Schema.Skill do
  @moduledoc """
  Skills are the main vector of attacks in a Battle, used to apply active or passive effects
  while in a Battle. Heroes have 3 normal Skills and an ultimate, which is its strongest Skill.
  Active Skills usually cost MP to be activated and have a cooldown in order to be activated again.
  Passive Skills usually cost no MP and activate by themselves, usually providing bonuses every turn.

  This is a match-locked resource, meaning once a match starts, its stats cannot be changed,
  and any changes made on the admin panel will only be applied on the next match.

  Skills can be unlocked with shards, and may have a user level_requirement
  """

  use Ecto.Schema
  use Arc.Ecto.Schema
  import Ecto.Changeset

  @derive {Jason.Encoder, except: [:__meta__, :match]}

  schema "skills" do
    field :image, Moba.Image.Type

    field :cooldown, :integer
    field :description, :string
    field :effects, :string
    field :code, :string
    field :enabled, :boolean
    field :current, :boolean
    field :mp_cost, :integer
    field :name, :string
    field :passive, :boolean, default: false
    field :ultimate, :boolean, default: false
    field :level, :integer
    field :duration, :integer
    field :level_requirement, :integer
    field :damage_type, :string

    # fields used by effects
    field :base_damage, :integer
    field :base_amount, :integer
    field :atk_multiplier, :float
    field :other_atk_multiplier, :float
    field :atk_regen_multiplier, :float
    field :hp_multiplier, :float
    field :other_hp_multiplier, :float
    field :hp_regen_multiplier, :float
    field :mp_multiplier, :float
    field :other_mp_multiplier, :float
    field :mp_regen_multiplier, :float
    field :extra_multiplier, :float
    field :armor_amount, :integer
    field :power_amount, :integer
    field :roll_number, :integer
    field :extra_amount, :integer

    # virtual fields used by Spells
    field :final, :boolean, virtual: true
    field :buff, :boolean, virtual: true
    field :debuff, :boolean, virtual: true
    field :defender_buff, :boolean, virtual: true
    field :attacker_debuff, :boolean, virtual: true

    belongs_to :match, Moba.Game.Schema.Match

    timestamps()
  end

  def changeset(skill, attrs) do
    skill
    |> cast(attrs, [
      :name,
      :code,
      :description,
      :effects,
      :mp_cost,
      :cooldown,
      :ultimate,
      :passive,
      :match_id,
      :atk_multiplier,
      :other_atk_multiplier,
      :atk_regen_multiplier,
      :hp_multiplier,
      :other_hp_multiplier,
      :hp_regen_multiplier,
      :mp_multiplier,
      :other_mp_multiplier,
      :mp_regen_multiplier,
      :extra_multiplier,
      :armor_amount,
      :power_amount,
      :roll_number,
      :extra_amount,
      :base_amount,
      :base_damage,
      :level,
      :duration,
      :enabled,
      :level_requirement,
      :damage_type,
      :current
    ])
    |> cast_attachments(attrs, [:image])
  end
end
