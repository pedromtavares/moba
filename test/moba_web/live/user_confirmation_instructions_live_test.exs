defmodule MobaWeb.UserConfirmationInstructionsLiveTest do
  use MobaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Moba.AccountsFixtures

  alias Moba.Accounts
  alias Moba.Repo

  setup do
    %{user: user_fixture()}
  end

  describe "Resend confirmation" do
    test "renders the resend confirmation page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/confirm")
      assert html =~ "Need a confirmation link?"
    end

    test "sends a usable confirmation token for an unconfirmed user", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/users/confirm")

      html =
        lv
        |> form("#resend_confirmation_form", user: %{email: user.email})
        |> render_submit()

      assert html =~ "If your email is in our system"
      assert has_element?(lv, "#account-resend-confirmation h1", "Check your inbox")

      assert user_token = Repo.get_by(Accounts.UserToken, user_id: user.id, context: "confirm")
      assert user_token.sent_to == user.email

      assert_received {:email, email}
      assert email.to == [{"", user.email}]
      [_, token] = Regex.run(~r{/users/confirm/([^\s]+)}, email.text_body)
      assert {:ok, confirmed_user} = Accounts.confirm_user(token)
      assert confirmed_user.id == user.id
      assert confirmed_user.confirmed_at
      refute Repo.get_by(Accounts.UserToken, user_id: user.id, context: "confirm")
    end

    test "does not send a confirmation token for an already confirmed user", %{
      conn: conn,
      user: user
    } do
      user |> Moba.Accounts.Schema.User.confirm_changeset() |> Repo.update!()

      {:ok, lv, _html} = live(conn, ~p"/users/confirm")

      html =
        lv
        |> form("#resend_confirmation_form", user: %{email: user.email})
        |> render_submit()

      assert html =~ "If your email is in our system"
      assert has_element?(lv, "#account-resend-confirmation h1", "Check your inbox")

      refute Repo.get_by(Accounts.UserToken, user_id: user.id, context: "confirm")
      refute_received {:email, _}
    end

    test "does not send confirmation token if email is invalid", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/confirm")

      html =
        lv
        |> form("#resend_confirmation_form", user: %{email: "unknown@example.com"})
        |> render_submit()

      assert html =~ "If your email is in our system"
      assert has_element?(lv, "#account-resend-confirmation h1", "Check your inbox")

      assert Repo.all(Accounts.UserToken) == []
      refute_received {:email, _}
    end
  end
end
