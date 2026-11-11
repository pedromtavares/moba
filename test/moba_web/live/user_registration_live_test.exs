defmodule MobaWeb.UserRegistrationLiveTest do
  use MobaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Moba.AccountsFixtures

  describe "Registration page" do
    test "renders registration page", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/users/register?from=training")

      assert html =~ "Create an account"
      assert html =~ "Sign In"
      refute has_element?(lv, "#guest-registration")
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

    test "shows a username error for another casing of an existing name", %{conn: conn} do
      user_fixture(username: "ArenaHero")
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      form = form(lv, "#registration_form", user: valid_user_attributes(username: "arenahero"))
      render_change(form)
      assert has_element?(lv, ".form-group:has(#user_username)", "has already been taken")

      render_submit(form)
      assert has_element?(lv, ".form-group:has(#user_username)", "has already been taken")
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
      skills = Enum.map(creation_skills(), & &1.id)
      avatar = base_avatar().id

      conn = conn |> get(~p"/start") |> recycle() |> post(~p"/start", %{"skills" => skills, "avatar" => avatar})

      guest_player_id = get_session(conn, :player_id)
      guest_player = Game.get_player!(guest_player_id)
      guest_hero = guest_player.current_pve_hero

      assert redirected_to(conn) == ~p"/training"
      assert guest_player.user_id == nil
      assert guest_hero.player_id == guest_player_id

      {:ok, lv, _html} =
        conn
        |> recycle()
        |> live(~p"/users/register?from=training")

      assert has_element?(lv, "#guest-roster-title", "Your hero")
      assert has_element?(lv, "#guest-registration-roster .guest-roster-hero strong", guest_hero.avatar.name)
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

      assert html_response(conn, 200) =~ "Start training"
    end

    test "guest onboarding keeps the roster and battle progress on the new account", %{conn: conn} do
      picks = Test.TeamHelper.team_picks(%{user: nil})

      conn =
        conn
        |> get(~p"/start")
        |> recycle()
        |> post(~p"/start", %{team: "true", roster: Jason.encode!(picks)})

      assert redirected_to(conn) == ~p"/training"
      guest = Game.get_player!(get_session(conn, :player_id))
      guest_scope = Game.TeamRuns.scope(guest)
      record = Game.TeamRuns.active(guest_scope, guest.id)

      {:ok, record} =
        Game.TeamRuns.update(guest_scope, record, fn run ->
          run = Test.TeamHelper.easy_target(run)
          run |> Game.TeamTraining.battle(hd(run.targets[1]).id) |> Test.TeamHelper.finish_team(guest_scope)
        end)

      before = Game.TeamRuns.state(record)
      assert before.heroes[1].hero.wins == 1
      assert [_encounter] = Game.TeamRuns.encounters(guest_scope, record.id)

      {:ok, registration, _} = conn |> recycle() |> live(~p"/users/register?from=training")
      assert has_element?(registration, "#guest-registration-sign-in[href='/users/log_in']")
      assert has_element?(registration, "#guest-registration-title", "Register to enter the Arena.")
      assert has_element?(registration, "#guest-registration-roster[aria-label='Training roster'] .guest-roster-league")
      refute has_element?(registration, "#guest-roster-title")

      for {unit, position} <- Enum.with_index(Game.TeamTraining.team(before), 1) do
        selector = "#guest-registration-roster li:nth-child(#{position})"
        assert has_element?(registration, selector <> " strong", unit.hero.avatar.name)
        assert has_element?(registration, selector <> " .guest-roster-caption > span", "Level #{unit.hero.level}")
      end

      attrs = valid_user_attributes()
      form = form(registration, "#registration_form", user: attrs)
      render_submit(form)
      conn = follow_trigger_action(form, conn)

      assert redirected_to(conn) == ~p"/base"
      assert get_session(conn, :player_id) == guest.id
      user = Accounts.get_user_by_email(attrs.email)
      assert Game.get_player!(guest.id).user_id == user.id
      refute Game.TeamRuns.get(guest_scope, record.id)
      scope = %{user: user, player_id: guest.id}
      claimed = Game.TeamRuns.get!(scope, record.id)
      assert claimed.state == record.state
      assert claimed.name == user.username
      assert Enum.all?(Game.TeamTraining.team(Game.TeamRuns.state(claimed)), &(&1.hero.name == user.username))
      assert [_encounter] = Game.TeamRuns.encounters(scope, record.id)

      {:ok, base, _} = conn |> recycle() |> live(~p"/base")
      assert has_element?(base, "#visible-team-#{record.id} a[href='/training?run=#{record.id}']")
      {:ok, training, _} = conn |> recycle() |> live(~p"/training")
      assert has_element?(training, "#team-training-page")

      for unit <- Game.TeamTraining.team(before) do
        assert has_element?(training, "#team-select-#{unit.id} strong", unit.hero.avatar.name)
      end
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
