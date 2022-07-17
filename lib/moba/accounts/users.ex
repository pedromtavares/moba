defmodule Moba.Accounts.Users do
  @moduledoc """
  Manages User records and progression via levels, shards and medals.

  Also includes logic for user-related PVP handling, which should be
  extracted to the Game context at some point (Player entity perhaps?).
  """

  alias Moba.{Repo, Accounts}
  alias Accounts.Schema.User
  alias Accounts.Query.UserQuery

  def get_user!(nil), do: nil
  def get_user!(id), do: Repo.get!(User, id)

  def get_user_with_unlocks!(id), do: get_user!(id) |> Repo.preload(:unlocks)

  def get_user_by_username(username), do: Repo.get_by(User, username: username)

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

  def set_online_now(user) do
    UserQuery.by_user(User, user)
    |> Repo.update_all(set: [last_online_at: DateTime.utc_now()])
  end
end
