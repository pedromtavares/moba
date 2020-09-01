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
    field :pvp_points, :integer, default: 0
    field :pvp_wins, :integer, default: 0
    field :pvp_losses, :integer, default: 0
    field :pvp_score, :map, default: %{}
    field :medal_count, :integer, default: 0
    field :shard_count, :integer, default: 0

    has_many :heroes, Moba.Game.Schema.Hero
    has_many :unlocks, Moba.Accounts.Schema.Unlock

    belongs_to :current_pve_hero, Moba.Game.Schema.Hero
    belongs_to :current_pvp_hero, Moba.Game.Schema.Hero

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
      :current_pvp_hero_id,
      :pvp_points
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
      :pvp_points,
      :pvp_wins,
      :pvp_losses,
      :pvp_score,
      :shard_count,
      :medal_count
    ])
    |> validate_required([:username, :email])
    |> validate_length(:username, min: 3, max: 15)
    |> unique_constraint(:email)
    |> unique_constraint(:username)
  end

  def admin_changeset(user, attrs) do
    user
    |> update_changeset(attrs)
    |> cast(attrs, [:is_admin, :is_bot])
  end

  def level_up(changeset, level, xp, shard_count) do
    changeset
    |> change(%{
      level: level + 1,
      experience: xp,
      shard_count: shard_count + 1
    })
  end
end
