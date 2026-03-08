defmodule MobaWeb.UserRegistrationLiveTest do
  use MobaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Moba.AccountsFixtures

  describe "Registration page" do
    test "renders registration page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/register")

      assert html =~ "Create an account"
      assert html =~ "Sign In"
    end

    test "redirects if already logged in", %{conn: conn} do
      result =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/register")
        |> follow_redirect(conn, ~p"/base")

      assert {:ok, _conn} = result
    end

    test "renders errors for invalid data", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      result =
        lv
        |> element("#registration_form")
        |> render_change(user: %{"email" => "with spaces", "password" => "no"})

      assert result =~ "Create an account"
      assert result =~ "must have the @ sign and no spaces"
      assert result =~ "should be at least 6 character"
    end

    test "keeps password value while validating other fields", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      result =
        lv
        |> element("#registration_form")
        |> render_change(user: %{"email" => "with spaces", "password" => "secret1"})

      assert result =~ ~s(value="secret1")
    end
  end

  describe "register user" do
    test "creates account and logs the user in", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      email = unique_user_email()
      form = form(lv, "#registration_form", user: valid_user_attributes(email: email))
      render_submit(form)
      conn = follow_trigger_action(form, conn)

      assert redirected_to(conn) == ~p"/base"
    end

    test "guest onboarding keeps the created hero and logs the user in", %{conn: conn} do
      skills = Enum.map(base_skills(), & &1.id)
      avatar = base_avatar().id

      conn = post(conn, ~p"/start", %{"skills" => skills, "avatar" => avatar})

      guest_player_id = get_session(conn, :player_id)
      guest_player = Game.get_player!(guest_player_id)
      guest_hero = guest_player.current_pve_hero

      assert redirected_to(conn) == ~p"/training"
      assert guest_player.user_id == nil
      assert guest_hero.player_id == guest_player_id

      {:ok, lv, _html} =
        conn
        |> recycle()
        |> live(~p"/users/register")

      attrs = valid_user_attributes()
      form = form(lv, "#registration_form", user: attrs)
      render_submit(form)
      conn = follow_trigger_action(form, conn)

      redirected_path = redirected_to(conn)
      user = Accounts.get_user_by_email(attrs.email)
      player = Game.get_player!(guest_player_id)

      assert redirected_path == ~p"/base"
      assert get_session(conn, :user_token)
      assert get_session(conn, :player_id) == guest_player_id
      assert user
      assert player.user_id == user.id
      assert player.current_pve_hero_id == guest_hero.id
      assert Game.get_hero!(guest_hero.id).player_id == guest_player_id
      assert Game.get_hero!(guest_hero.id).name == user.username

      conn =
        conn
        |> recycle()
        |> get(redirected_path)

      assert html_response(conn, 200) =~ "Train a new Hero"
    end

    test "renders errors for duplicated email", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      user = user_fixture(%{email: "test@email.com"})

      result =
        lv
        |> form("#registration_form",
          user: %{"email" => user.email, "password" => "valid_password"}
        )
        |> render_submit()

      assert result =~ "has already been taken"
    end
  end

  describe "registration navigation" do
    test "redirects to login page when the Log in button is clicked", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      {:ok, _login_live, login_html} =
        lv
        |> element(~s|a[href="/users/log_in"]|)
        |> render_click()
        |> follow_redirect(conn, ~p"/users/log_in")

      assert login_html =~ "Sign In"
    end
  end
end
