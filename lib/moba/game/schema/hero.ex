defmodule Moba.Game.Schema.Hero do
  @moduledoc """
  The most important Schema. A Hero can be created every match, and uses its Avatar
  for all of the base stats: Health, Energy, Attack, Power, Armor and Speed.

  A Hero starts at level 1 and levels up by gaining XP when beating
  opponents while Training.

  When a hero levels up it gains stats based on its Avatar, and
  on an even level (2, 4, 6, etc) it gains a skill level which
  it can use to level one of its skills.
  """

  use Ecto.Schema
  import Ecto.Changeset
  alias Moba.{Game, Accounts}
  require Integer

  schema "heroes" do
    field :name, :string
    field :experience, :integer, default: 0
    field :level, :integer, default: 1
    field :skill_levels_available, :integer, default: 0
    field :gold, :integer
    field :bot_difficulty, :string
    field :archived_at, :utc_datetime
    field :skill_order, {:array, :string}
    field :item_order, {:array, :string}

    # PVE related fields
    field :pve_total_turns, :integer
    field :pve_current_turns, :integer
    field :wins, :integer, default: 0
    field :losses, :integer, default: 0
    field :buybacks, :integer, default: 0
    field :total_gold_farm, :integer, default: 0
    field :total_xp_farm, :integer, default: 0
    field :pve_ranking, :integer
    field :finished_at, :utc_datetime
    field :refresh_targets_count, :integer, default: 0
    field :pve_state, :string
    field :pve_farming_turns, :integer
    field :pve_farming_started_at, :utc_datetime
    field :pve_tier, :integer

    embeds_many :pve_farming_rewards, Game.Schema.FarmingReward

    # PVP related fields
    field :pvp_picks, :integer, default: 0
    field :pvp_last_picked, :utc_datetime

    # League Challenge related fields
    field :league_tier, :integer
    field :league_step, :integer
    field :league_attempts, :integer, default: 0
    field :league_successes, :integer, default: 0

    # Base stats, set by its Avatar on creation
    field :total_hp, :integer
    field :total_mp, :integer
    field :atk, :integer
    field :speed, :integer
    field :armor, :integer
    field :power, :integer

    # Stats that get incremented by items
    field :item_hp, :integer, default: 0
    field :item_mp, :integer, default: 0
    field :item_atk, :integer, default: 0
    field :item_speed, :integer, default: 0
    field :item_armor, :integer, default: 0
    field :item_power, :integer, default: 0

    many_to_many :items, Game.Schema.Item, join_through: Game.Schema.HeroItem, on_replace: :delete
    many_to_many :skills, Game.Schema.Skill, join_through: Game.Schema.HeroSkill, on_replace: :delete

    has_many :targets, Game.Schema.Target, foreign_key: :attacker_id

    belongs_to :match, Game.Schema.Match
    belongs_to :avatar, Game.Schema.Avatar
    belongs_to :user, Accounts.Schema.User
    belongs_to :boss, Game.Schema.Hero
    belongs_to :skin, Game.Schema.Skin

    timestamps()
  end

  def changeset(hero, attrs) do
    hero
    |> cast(attrs, [
      :experience,
      :name,
      :level,
      :skill_order,
      :item_order,
      :wins,
      :losses,
      :pve_current_turns,
      :pve_total_turns,
      :pve_state,
      :pve_farming_turns,
      :pve_farming_started_at,
      :pve_tier,
      :bot_difficulty,
      :gold,
      :total_gold_farm,
      :total_xp_farm,
      :buybacks,
      :pve_ranking,
      :finished_at,
      :item_hp,
      :item_mp,
      :item_atk,
      :item_speed,
      :item_armor,
      :item_power,
      :skill_levels_available,
      :pvp_picks,
      :pvp_last_picked,
      :league_tier,
      :league_step,
      :league_attempts,
      :league_successes,
      :total_hp,
      :total_mp,
      :atk,
      :user_id,
      :archived_at,
      :boss_id,
      :skin_id,
      :match_id,
      :refresh_targets_count
    ])
    |> cast_embed(:pve_farming_rewards)
  end

  def create_changeset(hero, attrs, user, avatar, skills, items) do
    pve_tier = (user && user.pve_tier) || 0
    skill_order = Enum.filter(skills, &(!&1.passive)) |> Enum.map(& &1.code)
    item_order = Enum.filter(items, & &1.active) |> Enum.map(& &1.code)

    hero
    |> change(%{
      atk: avatar.atk,
      total_hp: avatar.total_hp,
      total_mp: avatar.total_mp,
      speed: avatar.speed,
      armor: avatar.armor,
      power: avatar.power,
      skill_order: skill_order,
      item_order: item_order
    })
    |> change(%{
      pve_state: "alive",
      pve_current_turns: Moba.turns_per_tier(),
      pve_total_turns: Moba.total_pve_turns(pve_tier),
      pve_tier: pve_tier,
      league_step: 0,
      league_tier: 0,
      gold: Moba.initial_gold(user)
    })
    |> changeset(attrs)
    |> put_assoc(:user, user)
    |> put_assoc(:avatar, avatar)
    |> put_assoc(:skills, skills)
    |> put_assoc(:items, items)
  end

  def replace_items(hero, nil), do: hero

  def replace_items(hero, items) do
    hero
    |> changeset(%{})
    |> put_assoc(:items, items)
  end

  def replace_skills(hero, nil), do: hero

  def replace_skills(hero, skills) do
    hero
    |> changeset(%{})
    |> put_assoc(:skills, skills)
  end

  def replace_farming_rewards(hero, rewards) do
    hero
    |> changeset(%{})
    |> put_embed(:pve_farming_rewards, rewards)
  end

  def level_up(changeset, level, xp) do
    hero = changeset.data
    changes = changeset.changes
    avatar = hero.avatar
    next_level = level + 1

    current_skill_levels = changes[:skill_levels_available] || hero.skill_levels_available

    skill_levels_available =
      cond do
        next_level > 28 -> current_skill_levels
        Integer.is_even(next_level) -> current_skill_levels + 1
        true -> current_skill_levels
      end

    changeset
    |> change(%{
      level: next_level,
      experience: xp,
      atk: (changes[:atk] || hero.atk) + avatar.atk_per_level,
      total_hp: (changes[:total_hp] || hero.total_hp) + avatar.hp_per_level,
      total_mp: (changes[:total_mp] || hero.total_mp) + avatar.mp_per_level,
      skill_levels_available: skill_levels_available
    })
  end
end
