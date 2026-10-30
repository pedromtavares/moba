defmodule MobaWeb.AnalyticsTest do
  use MobaWeb.ConnCase
  import Phoenix.LiveViewTest

  alias Moba.SiteSettings
  alias MobaWeb.CoreComponents

  setup do
    original = Application.fetch_env!(:moba, :analytics_allowed)
    on_exit(fn -> Application.put_env(:moba, :analytics_allowed, original) end)
    :ok
  end

  test "only exposes the configured ID on eligible production pages", %{conn: conn} do
    user = create_user() |> Ecto.Changeset.change(is_admin: true) |> Moba.Repo.update!()
    {:ok, _} = SiteSettings.update(user, %{analytics_enabled: true, analytics_measurement_id: "G-TEST123456"})
    page = %{conn | request_path: "/base"}

    Application.put_env(:moba, :analytics_allowed, false)
    assert MobaWeb.Analytics.measurement_id(page) == nil

    Application.put_env(:moba, :analytics_allowed, true)
    assert MobaWeb.Analytics.measurement_id(page) == "G-TEST123456"
    assert render_component(&CoreComponents.analytics/1, conn: page) =~ "G-TEST123456"

    for path <- ["/admin", "/admin/settings", "/dev/mailbox", "/users/log_in", "/auth/discord"] do
      assert MobaWeb.Analytics.measurement_id(%{page | request_path: path}) == nil
    end

    for host <- ["localhost", "127.0.0.1", "::1"] do
      assert MobaWeb.Analytics.measurement_id(%{page | host: host}) == nil
    end

    {:ok, _} = SiteSettings.update(user, %{analytics_enabled: false})
    assert MobaWeb.Analytics.measurement_id(page) == nil
  end

  test "the landing page and game layout use the same analytics setting", %{conn: conn} do
    hero = create_base_hero()
    user = hero.player.user |> Ecto.Changeset.change(is_admin: true) |> Moba.Repo.update!()
    {:ok, _} = SiteSettings.update(user, %{analytics_enabled: true, analytics_measurement_id: "G-TEST123456"})
    Application.put_env(:moba, :analytics_allowed, true)

    assert get(conn, "/") |> html_response(200) =~ ~s(name="google-analytics-id" content="G-TEST123456")
    player_conn = conn |> log_in_user(user) |> put_session(:player_id, hero.player_id)
    assert get(player_conn, "/base") |> html_response(200) =~ ~s(name="google-analytics-id" content="G-TEST123456")
    refute get(player_conn, "/admin/settings") |> html_response(200) =~ ~s(name="google-analytics-id")
  end
end
