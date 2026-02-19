defmodule Moba.Accounts.Users do
  @moduledoc """
  Manages User records and progression via levels, shards and medals.

  Also includes logic for user-related PVP handling, which should be
  extracted to the Game context at some point (Player entity perhaps?).
  """

  alias Moba.{Repo, Accounts}
  alias Accounts.Schema.User
  alias Accounts.Query.UserQuery
  alias Accounts.LegacyPassword

  def get_user!(nil), do: nil
  def get_user!(id), do: Repo.get!(User, id)

  def get_user_with_unlocks!(id), do: get_user!(id) |> Repo.preload(:unlocks)

  def get_user_by_username(username), do: UserQuery.with_username(User, username) |> Repo.all() |> List.first()

  def create_user(attrs \\ %{}) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  def update_user!(%User{} = user, attrs) do
    user
    |> User.update_changeset(attrs)
    |> Repo.update!()
  end

  @doc """
  Returns the user if the email and password match a Pow-generated pbkdf2 hash.
  Used during the migration window to verify existing users before bcrypt is in place.
  """
  def get_user_by_legacy_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: String.downcase(email))

    cond do
      is_nil(user) ->
        nil

      is_nil(user.password_hash) ->
        nil

      LegacyPassword.verify(password, user.password_hash) ->
        user

      true ->
        nil
    end
  end

  def set_online_now(user) do
    UserQuery.with_id(User, user.id)
    |> Repo.update_all(set: [last_online_at: DateTime.utc_now()])
  end
end
