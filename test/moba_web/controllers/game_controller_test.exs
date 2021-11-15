defmodule MobaWeb.GameControllerTest do
  use MobaWeb.ConnCase

  test "homepage loads", %{conn: conn} do
    conn = get(conn, "/")
    assert html_response(conn, 200) =~ "PRESS START"
  end

  test "user has active pve hero and is redirected to base", %{conn: conn} do
    hero = create_base_hero()

    conn = Pow.Plug.assign_current_user(conn, hero.user, otp_app: :moba) |> get("/")

    assert "/base" = redir_path = redirected_to(conn, 302)

    conn =
      conn
      |> recycle()
      |> Pow.Plug.assign_current_user(hero.user, otp_app: :moba)
      |> get(redir_path)

    assert html_response(conn, 200) =~ "Your Heroes"
  end

  test "user has active pvp hero and is redirected to base", %{conn: conn} do
    hero = create_pvp_hero()

    conn = Pow.Plug.assign_current_user(conn, hero.user, otp_app: :moba) |> get("/")

    assert "/base" = redir_path = redirected_to(conn, 302)

    conn =
      conn
      |> recycle()
      |> Pow.Plug.assign_current_user(hero.user, otp_app: :moba)
      |> get(redir_path)

    assert html_response(conn, 200) =~ "Arena"
  end

  test "start loads", %{conn: conn} do
    conn = get(conn, "/start")
    assert html_response(conn, 200) =~ "Pick your Avatar"
  end

  test "create", %{conn: conn} do
    skills = Enum.map(base_skills(), fn skill -> skill.id end)
    avatar = base_avatar().id

    conn = post(conn, "/start", %{"skills" => skills, "avatar" => avatar})

    assert "/game/pve" = redirected_to(conn, 302)
  end

  test "switch mode to pve", %{conn: conn} do
    hero = create_base_hero()

    conn = Pow.Plug.assign_current_user(conn, hero.user, otp_app: :moba) |> get("/game/pve")

    assert "/jungle" = redirected_to(conn, 302)
  end

  test "switch mode to pvp", %{conn: conn} do
    hero = create_pvp_hero()

    conn = Pow.Plug.assign_current_user(conn, hero.user, otp_app: :moba) |> get("/game/pvp")

    assert "/arena" = redirected_to(conn, 302)
  end
end
