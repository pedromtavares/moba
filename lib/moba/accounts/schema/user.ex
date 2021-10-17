defmodule Moba.Accounts.Schema.User do
  @moduledoc """
  This schema represents the User accounts in the app, with authorization
  being handled by Pow: https://github.com/danschultzer/pow
  """
  use Ecto.Schema
  use Pow.Ecto.Schema, password_min_length: 6

  use Pow.Extension.Ecto.Schema,
    extensions: [PowResetPassword, PowEmailConfirmation]

  import Ecto.Changeset

  alias Moba.{Game, Accounts}

  schema "users" do
    pow_user_fields()

    field :username, :string
    field :experience, :integer, default: 0
    field :level, :integer, default: 1
    field :is_admin, :boolean, default: false
    field :is_bot, :boolean, default: false
    field :is_guest, :boolean, default: false
    field :tutorial_step, :integer
    field :last_online_at, :utc_datetime
    field :status, :string
    field :ranking, :integer
    field :duel_score, :map, default: %{}
    field :duel_wins, :integer, default: 0
    field :duel_count, :integer, default: 0
    field :medal_count, :integer, default: 0
    field :shard_count, :integer, default: 0
    field :hero_collection, {:array, :map}
    field :season_tier, :integer, default: 0
    field :season_points, :integer, default: 0
    field :bot_codes, {:array, :string}
    field :bot_tier, :integer
    field :shard_limit, :integer, default: 100
    field :pve_tier, :integer, default: 0
    field :unread_messages_count, :integer, default: 0

    has_many :heroes, Game.Schema.Hero
    has_many :arena_picks, Game.Schema.ArenaPick
    has_many :unlocks, Accounts.Schema.Unlock
    has_many :duels, Game.Schema.Duel

    belongs_to :current_pve_hero, Game.Schema.Hero
    belongs_to :current_pvp_hero, Game.Schema.Hero
    belongs_to :title_quest, Game.Schema.Quest

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [
      :username,
      :experience,
      :level,
      :password,
      :email,
      :is_bot,
      :is_guest,
      :tutorial_step,
      :status,
      :current_pve_hero_id,
      :current_pvp_hero_id
    ])
    |> pow_changeset(attrs)
    |> pow_extension_changeset(attrs)
    |> validate_required([:username])
    |> validate_length(:username, min: 3, max: 15)
    |> unique_constraint(:email)
    |> unique_constraint(:username)
  end

  def experience_changeset(user, attrs) do
    user
    |> cast(attrs, [:experience, :level])
  end

  def update_changeset(user, attrs) do
    user
    |> cast(attrs, [
      :username,
      :experience,
      :level,
      :email,
      :tutorial_step,
      :last_online_at,
      :status,
      :ranking,
      :current_pve_hero_id,
      :current_pvp_hero_id,
      :duel_wins,
      :duel_count,
      :duel_score,
      :shard_count,
      :medal_count,
      :hero_collection,
      :season_points,
      :season_tier,
      :shard_limit,
      :pve_tier,
      :title_quest_id
    ])
    |> validate_required([:username, :email])
    |> validate_length(:username, min: 3, max: 15)
    |> unique_constraint(:email)
    |> unique_constraint(:username)
  end

  def admin_changeset(user, attrs) do
    user
    |> update_changeset(attrs)
    |> cast(attrs, [:is_admin, :is_bot, :bot_tier])
  end

  def level_up(changeset, level, xp) do
    changeset
    |> change(%{
      level: level + 1,
      experience: xp
    })
  end
end
