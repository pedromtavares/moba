defmodule Moba.Accounts.Schema.User do
  @moduledoc """
  This schema represents the User accounts in the app, with authorization
  being handled by Pow: https://github.com/danschultzer/pow
  """
  use Ecto.Schema
  use Pow.Ecto.Schema, password_min_length: 6

  use Pow.Extension.Ecto.Schema, extensions: [PowResetPassword]

  import Ecto.Changeset

  alias Moba.{Game, Accounts}

  schema "users" do
    pow_user_fields()

    field :username, :string
    field :last_online_at, :utc_datetime
    field :shard_count, :integer, default: 0
    field :is_admin, :boolean, default: false

    has_many :messages, Accounts.Schema.Message
    has_many :unlocks, Accounts.Schema.Unlock
    has_many :players, Game.Schema.Player

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [
      :username,
      :password,
      :email,
    ])
    |> pow_user_id_field_changeset(attrs)
    |> pow_password_changeset(attrs)
    |> pow_extension_changeset(attrs)
    |> validations_and_constraints()
  end

  def update_changeset(user, attrs) do
    user
    |> cast(attrs, [
      :username,
      :email,
      :shard_count
    ])
    |> validations_and_constraints()
  end

  def admin_changeset(user, attrs) do
    user
    |> update_changeset(attrs)
    |> cast(attrs, [:is_admin])
  end

  defp validations_and_constraints(changeset) do
    changeset
    |> validate_required([:username, :email])
    |> validate_length(:username, min: 3, max: 15)
    |> unique_constraint(:email)
    |> unique_constraint(:username)
  end
end
