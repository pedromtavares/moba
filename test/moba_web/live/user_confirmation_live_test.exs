defmodule MobaWeb.UserConfirmationLiveTest do
  use MobaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Moba.AccountsFixtures

  alias Moba.Accounts

  setup do
    %{user: user_fixture()}
  end

  describe "Confirm user" do
    test "renders confirmation page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/confirm/some-token")
      assert html =~ "Confirm your account"
    end

    test "does not confirm email with invalid token", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/users/confirm/invalid-token")

      lv |> form("#confirmation_form") |> render_submit()
      assert has_element?(lv, "#account-confirmation-expired")
      assert has_element?(lv, "#request-new-confirmation[href='/users/confirm']")

      refute Accounts.get_user!(user.id).confirmed_at
    end
  end
end
