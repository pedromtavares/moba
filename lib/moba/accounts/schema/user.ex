defmodule Moba.Accounts.Schema.User do
  use Ecto.Schema
  import Ecto.Changeset

  alias Moba.{Game, Accounts}
  import Ecto.Query, only: [from: 2]

  schema "users" do
    field :email, :string
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :confirmed_at, :naive_datetime
    field :password_hash, :string, redact: true

    field :username, :string
    field :last_online_at, :utc_datetime
    field :community_seen_at, :utc_datetime
    field :chat_burst_count, :integer, default: 0
    field :chat_last_message_at, :utc_datetime_usec
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
    |> normalize_email_change()
    |> cast_embed(:discord)
    |> validations_and_constraints()
    |> maybe_validate_unique_email([])
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
    |> unique_constraint(:email, name: :users_email_normalized_index)
    |> unique_constraint(:username)
  end

  defp validate_email(changeset, opts) do
    changeset
    |> normalize_email_change()
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
      |> put_change(:password_hash, nil)
      |> delete_change(:password)
    else
      changeset
    end
  end

  def normalize_email(email) when is_binary(email), do: email |> String.trim() |> String.downcase()

  defp normalize_email_change(changeset), do: update_change(changeset, :email, &normalize_email/1)

  defp maybe_validate_unique_email(changeset, opts) do
    email = get_change(changeset, :email)

    changeset =
      if Keyword.get(opts, :validate_email, true) && email do
        query = from u in __MODULE__, where: fragment("lower(btrim(?))", u.email) == ^email
        id = get_field(changeset, :id)
        query = if id, do: from(u in query, where: u.id != ^id), else: query

        if Moba.Repo.exists?(query) do
          add_error(changeset, :email, "has already been taken", validation: :unsafe_unique, fields: [:email])
        else
          changeset
        end
      else
        changeset
      end

    changeset
    |> unique_constraint(:email)
    |> unique_constraint(:email, name: :users_email_normalized_index)
  end
end
