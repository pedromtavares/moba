defmodule MobaWeb.PowResetPassword.MailerView do
  use MobaWeb, :mailer_view

  def subject(:reset_password, _assigns), do: "Reset password link"
end
