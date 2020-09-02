defmodule MobaWeb.PowEmailConfirmation.MailerView do
  use MobaWeb, :mailer_view

  def subject(:email_confirmation, _assigns), do: "Confirm your email address"
end
