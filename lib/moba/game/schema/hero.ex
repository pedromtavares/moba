defmodule Moba.Game.Schema.Hero do
  @moduledoc """
  The most important Schema. A Hero can be created every match, and uses its Avatar
  for all of the base stats: HP, MP, ATK, Power, Armor, Speed.

  A Hero starts at level 1 and levels up by gaining XP when beating
  opponents in the Jungle.

  It manages Items directly: Hero -> Items, but needs a Build to manage its skills:
  Hero -> Build -> Skills.

  When a hero levels up it gains stats based on its Avatar, and
  on an even level (2, 4, 6, etc) it gains a skill level which
  it can use to level one of the skills in its active_build.
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

    # PVE (Jungle) related fields
    field :pve_points, :integer
    field :pve_battles_available, :integer
    field :buffed_battles_available, :integer, default: 0
    field :xp_boosted_battles_available, :integer, default: 0
    field :wins, :integer, default: 0
    field :losses, :integer, default: 0
    field :ties, :integer, default: 0
    field :win_streak, :integer, default: 0
    field :loss_streak, :integer, default: 0
    field :total_farm, :integer, default: 0
    field :best_pve_streak, :integer, default: 0
    field :pve_ranking, :integer
    field :finished_pve, :boolean, default: false

    # PVP (Arena) related fields
    field :pvp_points, :integer
    field :pvp_battles_available, :integer
    field :pvp_ranking, :integer
    field :pvp_history, :map, default: %{}
    field :pvp_wins, :integer, default: 0
    field :pvp_losses, :integer, default: 0
    field :pvp_active, :boolean
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

    has_many :targets, Game.Schema.Target, foreign_key: :attacker_id
    has_many :builds, Game.Schema.Build

    belongs_to :active_build, Game.Schema.Build
    belongs_to :match, Game.Schema.Match
    belongs_to :avatar, Game.Schema.Avatar
    belongs_to :user, Accounts.Schema.User
    belongs_to :boss, Game.Schema.Hero

    timestamps()
  end

  def changeset(hero, attrs) do
    hero
    |> cast(attrs, [
      :experience,
      :name,
      :level,
      :win_streak,
      :loss_streak,
      :wins,
      :losses,
      :ties,
      :pve_battles_available,
      :pvp_battles_available,
      :buffed_battles_available,
      :xp_boosted_battles_available,
      :pve_points,
      :pvp_points,
      :bot_difficulty,
      :gold,
      :total_farm,
      :best_pve_streak,
      :pve_ranking,
      :finished_pve,
      :item_hp,
      :item_mp,
      :item_atk,
      :item_speed,
      :item_armor,
      :item_power,
      :skill_levels_available,
      :pvp_wins,
      :pvp_losses,
      :pvp_ranking,
      :pvp_history,
      :pvp_active,
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
      :active_build_id,
      :archived_at,
      :boss_id
    ])
  end

  def create_changeset(hero, attrs, user, avatar, match) do
    hero
    |> change(%{
      atk: avatar.atk,
      total_hp: avatar.total_hp,
      total_mp: avatar.total_mp,
      speed: avatar.speed,
      armor: avatar.armor,
      power: avatar.power
    })
    |> change(%{
      pve_battles_available: Moba.initial_battles(),
      xp_boosted_battles_available: Moba.xp_boosted_battles(),
      pve_points: 0,
      pvp_points: 0,
      league_step: 0,
      league_tier: 0,
      gold: Moba.initial_gold()
    })
    |> changeset(attrs)
    |> put_assoc(:match, match)
    |> put_assoc(:user, user)
    |> put_assoc(:avatar, avatar)
  end

  def replace_items(hero, nil), do: hero

  def replace_items(hero, items) do
    hero
    |> changeset(%{})
    |> put_assoc(:items, items)
  end

  def level_up(changeset, level, xp) do
    hero = changeset.data
    changes = changeset.changes
    avatar = hero.avatar
    next_level = level + 1

    current_skill_levels = changes[:skill_levels_available] || hero.skill_levels_available

    skill_levels_available =
      cond do
        Integer.is_even(next_level) -> current_skill_levels + 1
        next_level == Moba.max_hero_level() -> current_skill_levels + 2
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
