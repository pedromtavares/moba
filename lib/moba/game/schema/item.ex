defmodule Moba.Game.Schema.Item do
  @moduledoc """
  Items can be bought by Heroes to amplify their stats (base_hp, base_mp, etc)
  and to provide passive or active effects while in a Battle.

  Active Items usually cost MP to be activated and have a cooldown in order to be activated again.
  Passive Items usually cost no MP and activate by themselves.

  This is a match-locked resource, meaning once a match starts, its stats cannot be changed,
  and any changes made on the admin panel will only be applied on the next match.
  """

  use Ecto.Schema
  use Arc.Ecto.Schema
  import Ecto.Changeset

  @derive {Jason.Encoder, except: [:__meta__, :match]}
  schema "items" do
    field :image, Moba.Image.Type

    field :description, :string
    field :effects, :string
    field :code, :string
    field :name, :string
    field :rarity, :string
    field :active, :boolean, default: false
    field :passive, :boolean, default: false
    field :enabled, :boolean
    field :current, :boolean
    field :mp_cost, :integer, default: 0
    field :cooldown, :integer, default: 0
    field :duration, :integer, default: 0

    # increments item_hp, item_mp, etc in Hero
    field :base_hp, :integer, default: 0
    field :base_mp, :integer, default: 0
    field :base_atk, :integer, default: 0
    field :base_power, :integer, default: 0
    field :base_armor, :integer, default: 0
    field :base_speed, :integer, default: 0
    field :base_amount, :integer

    # fields used by effects
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

  def changeset(item, attrs) do
    item
    |> cast(attrs, [
      :name,
      :description,
      :effects,
      :code,
      :rarity,
      :active,
      :passive,
      :mp_cost,
      :cooldown,
      :duration,
      :base_hp,
      :base_mp,
      :base_atk,
      :base_power,
      :base_armor,
      :base_speed,
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
      :enabled,
      :current
    ])
    |> cast_attachments(attrs, [:image])
  end
end
