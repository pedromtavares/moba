defmodule MobaWeb.GameControllerTest do
  use MobaWeb.ConnCase

  test "homepage loads", %{conn: conn} do
    conn = get(conn, "/")
    assert html_response(conn, 200) =~ "ENTER THE ARENA"
  end

  test "user has active pve hero and is redirected to training", %{conn: conn} do
    hero = create_base_hero()

    conn = conn |> log_in_user(hero.player.user) |> get("/")

    assert "/training" = redir_path = redirected_to(conn, 302)

    conn =
      conn
      |> recycle()
      |> log_in_user(hero.player.user)
      |> get(redir_path)

    assert html_response(conn, 200) =~ "Battle Log"
  end

  test "start loads", %{conn: conn} do
    conn = get(conn, "/start")
    assert html_response(conn, 200) =~ "Pick your\nAvatar"
  end

  test "create as guest", %{conn: conn} do
    skills = Enum.map(base_skills(), fn skill -> skill.id end)
    avatar = base_avatar().id

    conn = post(conn, "/start", %{"skills" => skills, "avatar" => avatar})

    assert "/training" = redirected_to(conn, 302)
    assert get_session(conn, :player_id)
  end
end
