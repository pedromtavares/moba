defmodule Moba.Accounts do
  @moduledoc """
  Top-level domain of all account-wide logic
  """

  alias Moba.Accounts
  alias Accounts.{Users, Messages, Unlocks}

  # USERS

  defdelegate get_user!(id), to: Users

  defdelegate get_user_by_username(username), to: Users

  defdelegate get_user_with_unlocks!(id), to: Users

  defdelegate get_user_with_current_heroes!(id), to: Users

  defdelegate create_user(attrs), to: Users

  defdelegate update_user!(user, attrs), to: Users

  defdelegate update_tutorial_step!(user, step), to: Users

  defdelegate update_preferences!(user, preferences), to: Users

  defdelegate add_experience(user, experience), to: Users

  defdelegate create_guest(conn), to: Users

  defdelegate set_online_now(user), to: Users

  defdelegate set_available!(user), to: Users

  defdelegate set_unavailable!(user), to: Users

  defdelegate search(user), to: Users

  defdelegate duel_opponents(user, online_ids), to: Users

  # Player-related, should be extracted to Game context eventually: user -> player -> heroes

  defdelegate set_current_pve_hero!(user, hero_id), to: Users

  defdelegate season_points_for(tier), to: Users

  defdelegate season_tier_for(season_points), to: Users

  def user_duel_updates!(nil, _, _), do: nil

  def user_duel_updates!(user, duel_type, updates) do
    updated = Users.duel_updates!(user, duel_type, updates)
    Moba.update_pvp_ranking()
    updated
  end

  defdelegate ranking(limit), to: Users

  def update_ranking! do
    Users.update_ranking!()
    MobaWeb.broadcast("user-ranking", "ranking", %{})
  end

  defdelegate update_collection!(user, hero_collection), to: Users

  defdelegate reset_unread_messages_count(user), to: Users

  defdelegate increment_unread_messages_count_for_all_online_except(user), to: Users

  defdelegate shard_buyback_price(user), to: Users

  defdelegate shard_buyback!(user), to: Users

  defdelegate matchmaking_opponent(user), to: Users

  defdelegate normal_opponent(user), to: Users

  defdelegate elite_opponent(user), to: Users

  defdelegate bot_opponent(user), to: Users

  defdelegate manage_match_history(user, opponent), to: Users

  defdelegate normal_matchmaking_count(user), to: Users

  defdelegate elite_matchmaking_count(user), to: Users

  defdelegate closest_bot_time(user), to: Users

  # MESSAGES  

  defdelegate change_message(attrs \\ %{}), to: Messages

  def create_message!(attrs \\ %{}) do
    message = Messages.create_message!(attrs)
    MobaWeb.broadcast(message.channel, message.topic, message)
    message
  end

  defdelegate delete_message(message), to: Messages

  defdelegate get_message!(id), to: Messages

  defdelegate latest_messages(channel, topic, limit), to: Messages

  # UNLOCKS

  defdelegate create_unlock!(user, resource), to: Unlocks

  defdelegate unlocked_codes_for(user), to: Unlocks

  defdelegate price_to_unlock(resource), to: Unlocks
end
