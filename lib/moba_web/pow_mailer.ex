defmodule MobaWeb.PowMailer do
  use Pow.Phoenix.Mailer
  use Bamboo.Mailer, otp_app: :moba
  require Logger

  import Bamboo.Email

  def cast(%{user: user, subject: subject, text: text, html: html}) do
    new_email()
    |> to(user.email)
    |> from({"Browser MOBA", "browsermoba@gmail.com"})
    |> subject("Browser MOBA - #{subject}")
    |> html_body(html)
    |> text_body(text)
  end

  def process(email), do: deliver_now(email)
end
