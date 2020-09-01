defmodule Moba.Accounts do
  @moduledoc """
  Top-level domain of all account-wide logic

  As a top-level domain, it can access its siblings like Engine and Game, its parent (Moba)
  and all of its children (Users, Messages, etc). It cannot, however, access children of its
  siblings.
  """

  alias Moba.Accounts.{Users, Messages, Unlocks}

  # USERS

  def get_user!(id), do: Users.get!(id)

  def get_user_by_username!(username), do: Users.get_by_username!(username)

  def get_user_with_unlocks!(id), do: Users.get_with_unlocks!(id)

  def create_user(attrs), do: Users.create(attrs)

  def update_user!(user, attrs), do: Users.update!(user, attrs)

  def update_tutorial_step!(user, step), do: Users.update_tutorial_step!(user, step)

  def add_user_experience(user, experience), do: Users.add_experience(user, experience)

  def create_guest(conn), do: Users.create_guest(conn)

  def award_medals_and_shards(user, ranking), do: Users.award_medals_and_shards(user, ranking)

  def set_user_online_now(user), do: Users.set_online_now(user)

  # Player-related, should be extracted to Game context eventually: user -> player -> heroes

  def set_current_pve_hero!(user, hero_id), do: Users.set_current_pve_hero!(user, hero_id)

  def set_current_pvp_hero!(user, hero_id), do: Users.set_current_pvp_hero!(user, hero_id)

  def user_pvp_updates!(nil, _), do: nil

  def user_pvp_updates!(user_id, updates), do: get_user!(user_id) |> Users.pvp_updates!(updates)

  def user_pvp_decay!(user), do: Users.pvp_decay!(user)

  def ranking(limit \\ 20), do: Users.ranking(limit)

  def update_ranking!, do: Users.update_ranking!()

  # MESSAGES

  def latest_messages(limit \\ 10), do: Messages.latest(limit)

  def get_message!(id), do: Messages.get!(id)

  def change_message(attrs \\ %{}), do: Messages.change(attrs)

  def create_message!(attrs \\ %{}) do
    message = Messages.create!(attrs)
    MobaWeb.broadcast("chat", "message", message)
    message
  end

  def delete_message(message), do: Messages.delete(message)

  # UNLOCKS

  def create_unlock!(user, resource), do: Unlocks.create!(user, resource)

  def unlocked_codes_for(user), do: Unlocks.resource_codes_for(user)

  def price_to_unlock(resource), do: Unlocks.price(resource)
end
