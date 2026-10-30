defmodule Moba.Accounts.UserNotifierTest do
  use Moba.DataCase, async: true

  import Swoosh.TestAssertions

  alias Moba.Accounts.UserNotifier

  @user %{email: "hero@example.com", username: "PDK"}
  @url "https://example.com/users/reset-password/a-long-example-token?source=email&test=1"

  setup do
    Moba.AccountsFixtures.mail_sender_fixture()
    :ok
  end

  for {kind, title, action, expiry} <- [
        {:confirmation, "Welcome to the arena.", "Confirm account", "7 days"},
        {:reset_password, "Reset your password.", "Reset password", "24 hours"},
        {:update_email, "A new point of contact.", "Confirm new email", "7 days"}
      ] do
    test "#{kind} delivers a branded email with working HTML and plain-text links" do
      {:ok, email} = deliver(unquote(kind), @user, @url)

      assert_email_sent(email)
      assert email.to == [{"", @user.email}]
      assert email.from == {"Browser MOBA", "noreply@example.com"}

      html = LazyHTML.from_document(email.html_body)
      assert html |> LazyHTML.query("h1") |> LazyHTML.text() |> String.trim() == unquote(title)

      for selector <- ["#email-action", "#email-fallback-link"] do
        assert html |> LazyHTML.query(selector) |> LazyHTML.attribute("href") == [@url]
      end

      assert html |> LazyHTML.query("#email-action") |> LazyHTML.text() =~ unquote(action)
      assert LazyHTML.text(html) =~ "This link expires in #{unquote(expiry)}."
      assert email.text_body =~ unquote(action)
      assert email.text_body =~ @url
      assert email.text_body =~ "This link expires in #{unquote(expiry)}."
      assert email.text_body =~ "Hi PDK,"

      # The brand image travels with the email; no remote assets or tracking requests.
      assert [%{type: :inline, cid: "browsermoba-helmet", content_type: "image/png"} = logo] = email.attachments
      assert <<137, 80, 78, 71, _::binary>> = Swoosh.Attachment.get_content(logo)
      assert html |> LazyHTML.query("img") |> LazyHTML.attribute("src") == ["cid:browsermoba-helmet"]
      assert Enum.empty?(LazyHTML.query(html, "script, link, iframe"))
    end
  end

  test "escapes user content and action URLs in the HTML" do
    user = %{@user | username: ~s|<img src=x onerror="alert(1)">|}
    url = @url <> ~s|&value="<script>alert(1)</script>|
    {:ok, email} = UserNotifier.deliver_reset_password_instructions(user, url)
    html = LazyHTML.from_document(email.html_body)

    assert LazyHTML.text(html) =~ user.username
    assert html |> LazyHTML.query("#email-action") |> LazyHTML.attribute("href") == [url]
    assert Enum.empty?(LazyHTML.query(html, "script, [onerror]"))
    assert email.text_body =~ user.username
  end

  test "supports recipients without a username" do
    {:ok, email} = UserNotifier.deliver_reset_password_instructions(%{email: @user.email}, @url)
    assert email.text_body =~ "Hi hero,"
  end

  test "does not deliver without a configured sender" do
    Moba.SiteSettings.get() |> Ecto.Changeset.change(mail_from: nil) |> Repo.update!()

    assert {:error, :mail_sender_not_configured} = UserNotifier.deliver_reset_password_instructions(@user, @url)
    refute_email_sent()
  end

  defp deliver(:confirmation, user, url), do: UserNotifier.deliver_confirmation_instructions(user, url)
  defp deliver(:reset_password, user, url), do: UserNotifier.deliver_reset_password_instructions(user, url)
  defp deliver(:update_email, user, url), do: UserNotifier.deliver_update_email_instructions(user, url)
end
