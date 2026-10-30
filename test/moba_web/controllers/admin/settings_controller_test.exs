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
             settings: %{analytics_enabled: true, analytics_measurement_id: "G-TEST123456"}
           )
           |> redirected_to() == "/"

    refute SiteSettings.get().analytics_enabled
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
end
