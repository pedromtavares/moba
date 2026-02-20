defmodule Moba.Accounts.Schema.User do
  use Ecto.Schema
  import Ecto.Changeset

  alias Moba.{Game, Accounts}

  schema "users" do
    field :email, :string
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :confirmed_at, :naive_datetime
    field :password_hash, :string

    field :username, :string
    field :last_online_at, :utc_datetime
    field :community_seen_at, :utc_datetime
    field :shard_count, :integer, default: 0
    field :is_admin, :boolean, default: false

    has_many :messages, Accounts.Schema.Message
    has_many :unlocks, Accounts.Schema.Unlock
    has_many :players, Game.Schema.Player

    embeds_one :discord, Accounts.Schema.Discord, on_replace: :update

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:username, :password, :email])
    |> validate_email([])
    |> validate_password([])
    |> validations_and_constraints()
  end

  def update_changeset(user, attrs) do
    user
    |> cast(attrs, [:username, :email, :shard_count, :community_seen_at])
    |> cast_embed(:discord)
    |> validations_and_constraints()
  end

  def admin_changeset(user, attrs) do
    user
    |> update_changeset(attrs)
    |> cast(attrs, [:is_admin])
  end

  def registration_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email, :password, :username])
    |> validate_email(opts)
    |> validate_password(opts)
    |> validate_required([:username])
    |> validate_length(:username, min: 3, max: 15)
    |> unique_constraint(:username)
  end

  def settings_changeset(user, attrs) do
    user
    |> cast(attrs, [:username, :email, :password])
    |> validate_email([])
    |> maybe_validate_password()
    |> validations_and_constraints()
  end

  def email_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email])
    |> validate_email(opts)
    |> case do
      %{changes: %{email: _}} = changeset -> changeset
      %{} = changeset -> add_error(changeset, :email, "did not change")
    end
  end

  def password_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:password])
    |> validate_confirmation(:password, message: "does not match password")
    |> validate_password(opts)
  end

  def confirm_changeset(user) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    change(user, confirmed_at: now)
  end

  def valid_password?(%__MODULE__{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Bcrypt.no_user_verify()
    false
  end

  def validate_current_password(changeset, password) do
    if valid_password?(changeset.data, password) do
      changeset
    else
      add_error(changeset, :current_password, "is not valid")
    end
  end

  defp validations_and_constraints(changeset) do
    changeset
    |> validate_required([:username, :email])
    |> validate_length(:username, min: 3, max: 15)
    |> unique_constraint(:email)
    |> unique_constraint(:username)
  end

  defp validate_email(changeset, opts) do
    changeset
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> validate_length(:email, max: 160)
    |> maybe_validate_unique_email(opts)
  end

  defp maybe_validate_password(changeset) do
    if get_change(changeset, :password) do
      changeset
      |> validate_confirmation(:password, message: "does not match password")
      |> validate_password([])
    else
      changeset
    end
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 6, max: 72)
    |> maybe_hash_password(opts)
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      |> validate_length(:password, max: 72, count: :bytes)
      |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  defp maybe_validate_unique_email(changeset, opts) do
    if Keyword.get(opts, :validate_email, true) do
      changeset
      |> unsafe_validate_unique(:email, Moba.Repo)
      |> unique_constraint(:email)
    else
      changeset
    end
  end
end
