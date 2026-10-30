defmodule MobaWeb.V2.PolishLiveTest do
  use MobaWeb.ConnCase
  import Phoenix.LiveViewTest
  import Moba.AccountsFixtures

  test "skill unlocks show requirements, then ownership and updated balance", %{conn: conn} do
    hero = create_base_hero()
    skill = Game.get_skill_by_code!("decay", false, 5)
    Moba.Repo.update!(Ecto.Changeset.change(skill, level_requirement: 1, enabled: true))
    conn = conn |> log_in_user(hero.player.user) |> put_session(:player_id, hero.player_id)
    {:ok, locked, _} = live(conn, "/tavern")
    assert has_element?(locked, "#skill-#{skill.id} .tavern-unlock-button[disabled]")
    assert has_element?(locked, "#skill-#{skill.id} .tavern-unlock-requirement")
    assert has_element?(locked, "#skill-details-#{skill.id} summary")
    Accounts.update_user!(hero.player.user, %{shard_count: 100})
    {:ok, view, _} = live(conn, "/tavern")
    view |> element("#skill-#{skill.id} #unlock-#{skill.code}") |> render_click()
    assert has_element?(view, "#skill-#{skill.id} [data-unlocked=true] .tavern-owned")
    refute has_element?(view, "#skill-#{skill.id} #unlock-#{skill.code}")
    assert has_element?(view, "#tavern-shards strong", "0")
    assert has_element?(view, "#game-feedback-info", "unlocked")
    assert skill.code in Accounts.unlocked_codes_for(Accounts.get_user!(hero.player.user_id))
  end

  test "settings retain validation and save feedback in the preview shell", %{conn: conn} do
    user = user_fixture()
    {:ok, view, _} = live(log_in_user(conn, user), "/users/settings")
    assert has_element?(view, "#account-settings #save-account-settings")
    view |> form("#settings_form", user: %{username: user.username, email: "invalid"}) |> render_submit()
    assert has_element?(view, "#settings_form", "must have the @ sign")
    email = unique_user_email()
    view |> form("#settings_form", user: %{username: user.username, email: email}) |> render_submit()
    assert Accounts.get_user_by_email(email)
    assert has_element?(view, "#game-feedback-info", "Profile updated")
    view |> element("#game-feedback-info button") |> render_click()
    refute has_element?(view, "#game-feedback-info")
  end

  test "recovery acknowledges unknown emails without revealing account existence", %{conn: conn} do
    {:ok, view, _} = live(conn, "/users/reset_password")
    assert has_element?(view, "#account-recovery #send-reset-link")
    view |> form("#reset_password_form", user: %{email: "unknown@example.com"}) |> render_submit()
    assert has_element?(view, "#recovery-sent")
    assert has_element?(view, "#account-recovery-title", "Check your inbox")
    assert has_element?(view, "#reset_password_form input[value='']")
    assert has_element?(view, "#send-reset-link", "Send another link")
  end

  test "reset and confirmation screens keep their original form contracts", %{conn: conn} do
    user = user_fixture()
    token = extract_user_token(fn url -> Accounts.deliver_user_reset_password_instructions(user, url) end)
    {:ok, reset, _} = live(conn, "/users/reset_password/#{token}")
    assert has_element?(reset, "#account-reset #reset-account-password")

    reset
    |> form("#reset_password_form", user: %{password: "short", password_confirmation: "different"})
    |> render_change()

    assert has_element?(reset, "#reset_password_form", "does not match password")
    {:ok, confirm, _} = live(conn, "/users/confirm/invalid-token")
    assert has_element?(confirm, "#account-confirmation #confirmation_form")
    assert has_element?(confirm, "#confirmation_form input[type=hidden][value='invalid-token']")
    confirm |> form("#confirmation_form", user: %{token: "invalid-token"}) |> render_submit()
    assert has_element?(confirm, "#account-confirmation-expired #request-new-confirmation[href='/users/confirm']")
    refute has_element?(confirm, "#confirmation_form")
    {:ok, expired, _} = live(conn, "/users/reset_password/invalid")
    assert has_element?(expired, "#account-reset-expired #request-new-reset[href='/users/reset_password']")
    refute has_element?(expired, "#reset_password_form")
    {:ok, resend, _} = live(conn, "/users/confirm")
    assert has_element?(resend, "#account-resend-confirmation #resend_confirmation_form")
  end

  test "creation uses the modern surface and shared feedback layer", %{conn: conn} do
    {:ok, view, _} = live(conn, "/start")
    assert has_element?(view, "#create-new")
    assert has_element?(view, "#create-new #invoke-modern")
    assert has_element?(view, "#game-feedback")
  end
end
