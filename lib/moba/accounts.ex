defmodule Moba.Accounts do
  @moduledoc """
  Top-level domain of all account-wide logic
  """

  alias Moba.Accounts
  alias Accounts.{Auth, Users, Messages, Unlocks}

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

  defdelegate notification_count(player), to: Messages

  # UNLOCKS

  defdelegate buy_unlock!(user, resource), to: Unlocks

  defdelegate create_unlock!(user, resource_code), to: Unlocks

  defdelegate unlocked_codes_for(user), to: Unlocks

  defdelegate price_to_unlock(resource), to: Unlocks

  # AUTH

  defdelegate get_user_by_email(email), to: Auth

  defdelegate get_user_by_email_and_password(email, password), to: Auth

  defdelegate register_user(attrs), to: Auth

  defdelegate change_user_registration(user, attrs \\ %{}), to: Auth

  defdelegate change_user_settings(user, attrs \\ %{}), to: Auth

  defdelegate update_user_settings(user, attrs), to: Auth

  defdelegate change_user_email(user, attrs \\ %{}), to: Auth

  defdelegate apply_user_email(user, password, attrs), to: Auth

  defdelegate update_user_email(user, token), to: Auth

  defdelegate deliver_user_update_email_instructions(user, current_email, update_email_url_fun), to: Auth

  defdelegate change_user_password(user, attrs \\ %{}), to: Auth

  defdelegate update_user_password(user, password, attrs), to: Auth

  defdelegate generate_user_session_token(user), to: Auth

  defdelegate get_user_by_session_token(token), to: Auth

  defdelegate delete_user_session_token(token), to: Auth

  defdelegate deliver_user_confirmation_instructions(user, confirmation_url_fun), to: Auth

  defdelegate confirm_user(token), to: Auth

  defdelegate deliver_user_reset_password_instructions(user, reset_password_url_fun), to: Auth

  defdelegate get_user_by_reset_password_token(token), to: Auth

  defdelegate reset_user_password(user, attrs), to: Auth
end
