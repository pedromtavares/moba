defmodule Moba.Accounts.UserNotifier do
  alias Moba.Emails.UserEmail
  alias Moba.Mailer
  alias Moba.SiteSettings

  defp deliver(user, url, kind) do
    case SiteSettings.get() do
      %{mail_from: address, mail_from_name: name} when is_binary(address) and address != "" ->
        email = UserEmail.build(user, url, kind, {name, address})

        with {:ok, _metadata} <- Mailer.deliver(email) do
          {:ok, email}
        end

      _ ->
        {:error, :mail_sender_not_configured}
    end
  end

  @doc """
  Deliver instructions to confirm account.
  """
  def deliver_confirmation_instructions(user, url) do
    deliver(user, url, :confirmation)
  end

  @doc """
  Deliver instructions to reset a user password.
  """
  def deliver_reset_password_instructions(user, url) do
    deliver(user, url, :reset_password)
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    deliver(user, url, :update_email)
  end
end
