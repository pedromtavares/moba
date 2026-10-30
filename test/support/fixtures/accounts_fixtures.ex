defmodule Moba.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Moba.Accounts` context.
  """

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"
  def valid_user_password, do: "hello world!"

  def mail_sender_fixture do
    Moba.SiteSettings.get()
    |> Ecto.Changeset.change(mail_from: "noreply@example.com", mail_from_name: "Browser MOBA")
    |> Moba.Repo.update!()
  end

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_user_email(),
      password: valid_user_password(),
      username: "user#{System.unique_integer([:positive])}"
    })
  end

  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> Moba.Accounts.register_user()

    user
  end

  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end
end
