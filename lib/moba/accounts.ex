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

  defdelegate create_user(attrs), to: Users

  defdelegate update_user!(user, attrs), to: Users

  defdelegate set_online_now(user), to: Users

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
