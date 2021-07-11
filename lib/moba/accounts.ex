defmodule Moba.Accounts do
  @moduledoc """
  Top-level domain of all account-wide logic

  As a top-level domain, it can access its siblings like Engine and Game, its parent (Moba)
  and all of its children (Users, Messages, etc). It cannot, however, access children of its
  siblings.
  """

  alias Moba.{Repo, Game, Accounts}
  alias Accounts.{Users, Messages, Unlocks}

  # USERS

  def get_user!(id), do: Users.get!(id)

  def get_user_by_username!(username), do: Users.get_by_username!(username)

  def get_user_with_unlocks!(id), do: Users.get_with_unlocks!(id)

  def get_user_with_current_heroes!(id), do: Users.get_with_current_heroes!(id)

  def create_user(attrs), do: Users.create(attrs)

  def update_user!(user, attrs), do: Users.update!(user, attrs)

  def update_tutorial_step!(user, step), do: Users.update_tutorial_step!(user, step)

  def add_user_experience(user, experience), do: Users.add_experience(user, experience)

  def create_guest(conn), do: Users.create_guest(conn)

  def award_medals_and_shards(user, ranking), do: Users.award_medals_and_shards(user, ranking)

  def set_user_online_now(user), do: Users.set_online_now(user)

  def user_search(user), do: Users.search(user)

  defdelegate easy_mode?(user), to: Users

  # Player-related, should be extracted to Game context eventually: user -> player -> heroes

  defdelegate set_current_pve_hero!(user, hero_id), to: Users

  defdelegate set_current_pvp_hero!(user, hero_id), to: Users

  defdelegate clear_active_players!, to: Users

  defdelegate manage_season_points!(user), to: Users

  defdelegate season_points_for(tier), to: Users

  def maybe_archive_current_pve_hero(%{current_pve_hero_id: hero_id} = user) when not is_nil(hero_id) do
    %{current_pve_hero: pve_hero} = Repo.preload(user, :current_pve_hero)

    unless pve_hero.finished_pve do
      Game.update_hero!(pve_hero, %{archived_at: DateTime.utc_now()})
    end
  end

  def maybe_archive_current_pve_hero(user), do: user

  def user_pvp_updates!(nil, _), do: nil

  def user_pvp_updates!(user_id, updates), do: get_user!(user_id) |> Users.pvp_updates!(updates)

  def user_pvp_decay!(user), do: Users.pvp_decay!(user)

  defdelegate ranking(limit), to: Users

  defdelegate update_ranking!, to: Users

  defdelegate reset_shard_limits!, to: Users

  defdelegate finish_pve!(user, hero_collection, shards), to: Users

  defdelegate pve_shards_for(user, league_tier), to: Users

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
