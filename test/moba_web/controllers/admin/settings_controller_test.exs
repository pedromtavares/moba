defmodule MobaWeb.Admin.SettingsControllerTest do
  use MobaWeb.ConnCase

  alias Moba.SiteSettings

  setup %{conn: conn} do
    hero = create_base_hero()
    admin = hero.player.user |> Ecto.Changeset.change(is_admin: true) |> Moba.Repo.update!()
    admin_conn = conn |> log_in_user(admin) |> put_session(:player_id, hero.player_id)
    %{admin: admin, admin_conn: admin_conn}
  end

  test "requires login and admin permissions", %{conn: conn} do
    assert get(conn, "/admin/settings") |> redirected_to() == "/users/log_in"

    user = create_user()
    user_conn = log_in_user(conn, user)
    assert get(user_conn, "/admin/settings") |> redirected_to() == "/"

    assert put(user_conn, "/admin/settings",
             settings: %{
               analytics_enabled: true,
               analytics_measurement_id: "G-TEST123456",
               mail_from: "attacker@example.com",
               mail_from_name: "Unauthorized sender"
             }
           )
           |> redirected_to() == "/"

    refute SiteSettings.get().analytics_enabled
    assert is_nil(SiteSettings.get().mail_from)
    assert SiteSettings.update(user, %{analytics_enabled: true}) == {:error, :unauthorized}
  end

  test "new installations have analytics disabled and no account ID", %{admin_conn: conn} do
    html = get(conn, "/admin/settings") |> html_response(200)
    document = LazyHTML.from_document(html)
    assert LazyHTML.query(document, "#torch-form") |> LazyHTML.to_tree() != []
    input = LazyHTML.query(document, "#settings_analytics_measurement_id")
    assert LazyHTML.to_tree(input) != []
    assert LazyHTML.attribute(input, "value") in [[], [""]]
    refute SiteSettings.get().analytics_enabled
    assert is_nil(SiteSettings.get().analytics_measurement_id)
    assert is_nil(SiteSettings.get().mail_from)
    assert SiteSettings.get().mail_from_name == "Browser MOBA"
    assert LazyHTML.query(document, "#settings_mail_from") |> LazyHTML.attribute("type") == ["email"]
    assert LazyHTML.query(document, "#settings_mail_from_name") |> LazyHTML.attribute("value") == ["Browser MOBA"]
  end

  test "saves and normalizes a GA4 measurement ID", %{admin_conn: conn} do
    conn =
      put(conn, "/admin/settings", settings: %{analytics_enabled: true, analytics_measurement_id: " g-test123456 "})

    assert redirected_to(conn) == "/admin/settings"
    assert %{analytics_enabled: true, analytics_measurement_id: "G-TEST123456"} = SiteSettings.get()
  end

  test "rejects missing IDs, legacy IDs and executable snippets", %{admin_conn: conn} do
    for id <- ["", "UA-12345-1", "GTM-ABCDE", "<script>alert(1)</script>", "G-TEST\" onload=\"alert(1)"] do
      response = put(conn, "/admin/settings", settings: %{analytics_enabled: true, analytics_measurement_id: id})
      assert html_response(response, 422) =~ "GA4 measurement ID"
      refute SiteSettings.get().analytics_enabled
      assert is_nil(SiteSettings.get().analytics_measurement_id)
    end
  end

  test "can disable analytics and clear a previously saved ID", %{admin: admin, admin_conn: conn} do
    {:ok, _} = SiteSettings.update(admin, %{analytics_enabled: true, analytics_measurement_id: "G-TEST123456"})

    assert put(conn, "/admin/settings", settings: %{analytics_enabled: false, analytics_measurement_id: ""})
           |> redirected_to() == "/admin/settings"

    assert %{analytics_enabled: false, analytics_measurement_id: nil} = SiteSettings.get()
  end

  test "saves the sender alongside analytics and applies it to account emails immediately", %{admin_conn: conn} do
    response =
      put(conn, "/admin/settings",
        settings: %{
          analytics_enabled: true,
          analytics_measurement_id: "G-TEST123456",
          mail_from: "  noreply@example.com  ",
          mail_from_name: "  My MOBA  "
        }
      )

    assert redirected_to(response) == "/admin/settings"
    assert %{analytics_enabled: true, mail_from: "noreply@example.com", mail_from_name: "My MOBA"} = SiteSettings.get()

    for deliver <- [
          &Moba.Accounts.UserNotifier.deliver_confirmation_instructions/2,
          &Moba.Accounts.UserNotifier.deliver_reset_password_instructions/2,
          &Moba.Accounts.UserNotifier.deliver_update_email_instructions/2
        ] do
      {:ok, email} = deliver.(%{email: "hero@example.com"}, "https://example.com/action")
      assert email.from == {"My MOBA", "noreply@example.com"}
    end

    response =
      put(conn, "/admin/settings", settings: %{mail_from: "support@example.com", mail_from_name: "Updated MOBA"})

    assert redirected_to(response) == "/admin/settings"

    {:ok, email} =
      Moba.Accounts.UserNotifier.deliver_reset_password_instructions(
        %{email: "hero@example.com"},
        "https://example.com/action"
      )

    assert email.from == {"Updated MOBA", "support@example.com"}
    assert SiteSettings.get().analytics_enabled
  end

  test "rejects invalid sender addresses and names without changing the saved sender", %{admin: admin, admin_conn: conn} do
    {:ok, _} = SiteSettings.update(admin, %{mail_from: "noreply@example.com", mail_from_name: "My MOBA"})

    for attrs <- [
          %{mail_from: "invalid"},
          %{mail_from: "One <one@example.com>"},
          %{mail_from: "one@example.com,two@example.com"},
          %{mail_from: "one@example.com\r\nBcc: two@example.com"},
          %{mail_from: String.duplicate("a", 250) <> "@example.com"},
          %{mail_from_name: ""},
          %{mail_from_name: "My MOBA\r\nBcc: two@example.com"},
          %{mail_from_name: "Other <one@example.com>"},
          %{mail_from_name: String.duplicate("a", 101)}
        ] do
      assert put(conn, "/admin/settings", settings: attrs) |> html_response(422) =~ "Email sender"
      assert %{mail_from: "noreply@example.com", mail_from_name: "My MOBA"} = SiteSettings.get()
    end
  end

  test "can clear the sender without affecting analytics", %{admin: admin, admin_conn: conn} do
    {:ok, _} =
      SiteSettings.update(admin, %{
        mail_from: "noreply@example.com",
        analytics_enabled: true,
        analytics_measurement_id: "G-TEST123456"
      })

    assert put(conn, "/admin/settings", settings: %{mail_from: ""}) |> redirected_to() == "/admin/settings"
    assert %{mail_from: nil, analytics_enabled: true, analytics_measurement_id: "G-TEST123456"} = SiteSettings.get()
  end
end
