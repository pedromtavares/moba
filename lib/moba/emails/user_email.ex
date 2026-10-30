defmodule Moba.Emails.UserEmail do
  @moduledoc """
  Shared, self-contained HTML and plain-text account emails.
  """
  use Phoenix.Component

  import Swoosh.Email, only: [new: 0, to: 2, from: 2, subject: 2, text_body: 2, html_body: 2, attachment: 2]

  embed_templates "user_email/*"

  def build(user, url, kind, sender) do
    copy = copy(kind)
    name = Map.get(user, :username) || "hero"
    assigns = Map.merge(copy, %{name: name, url: url})

    new()
    |> to(user.email)
    |> from(sender)
    |> subject(copy.subject)
    |> text_body("""
    BROWSER MOBA

    #{copy.title}

    Hi #{name},

    #{copy.message}

    #{copy.action}:
    #{url}

    This link expires in #{copy.expiry}.

    #{copy.notice}
    """)
    |> html_body(assigns |> message() |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary())
    |> attachment(
      Swoosh.Attachment.new(Application.app_dir(:moba, "priv/emails/helmet.png"),
        filename: "helmet.png",
        content_type: "image/png",
        type: :inline,
        cid: "browsermoba-helmet"
      )
    )
  end

  defp copy(:reset_password) do
    %{
      subject: "Reset your Browser MOBA password",
      chapter: "ACCOUNT RECOVERY",
      title: "Reset your password.",
      message: "Choose a new password and get back to your heroes.",
      action: "Reset password",
      expiry: "24 hours",
      notice: "Didn't request a password reset? You can ignore this email. Your password will stay the same."
    }
  end

  defp copy(:confirmation) do
    %{
      subject: "Confirm your Browser MOBA account",
      chapter: "YOUR JOURNEY BEGINS",
      title: "Welcome to the arena.",
      message: "Confirm your email address to secure your Browser MOBA account.",
      action: "Confirm account",
      expiry: "7 days",
      notice: "Didn't create a Browser MOBA account? You can ignore this email."
    }
  end

  defp copy(:update_email) do
    %{
      subject: "Confirm your new Browser MOBA email",
      chapter: "ACCOUNT UPDATE",
      title: "A new point of contact.",
      message: "Confirm this email address to finish updating your Browser MOBA account.",
      action: "Confirm new email",
      expiry: "7 days",
      notice: "Didn't request this email change? You can ignore this email. Your account will stay the same."
    }
  end
end
