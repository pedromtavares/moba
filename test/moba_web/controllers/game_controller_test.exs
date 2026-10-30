defmodule MobaWeb.GameControllerTest do
  use MobaWeb.ConnCase

  test "homepage loads", %{conn: conn} do
    conn = get(conn, "/")
    document = conn |> html_response(200) |> LazyHTML.from_document()

    assert Enum.count(LazyHTML.query(document, "#landing-entrance")) == 1
    assert LazyHTML.query(document, "#landing-entrance") |> LazyHTML.attribute("href") == ["/start"]
    assert Enum.count(LazyHTML.query(document, "#landing-stats .landing-stat")) == 3

    for id <- ["players", "heroes", "matches"] do
      value = document |> LazyHTML.query("#landing-stat-#{id} dd") |> LazyHTML.text()
      assert value =~ ~r/^\d{1,3}(,\d{3})*$/
    end

    assert [mobile] = LazyHTML.query(document, "#landing-artwork source") |> LazyHTML.attribute("srcset")
    assert mobile == "/images/landing/home-heroes-mobile-v1.webp"
    assert [desktop] = LazyHTML.query(document, "#landing-artwork-image") |> LazyHTML.attribute("src")
    assert desktop == "/images/landing/home-heroes-v5.png"
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
    html = html_response(conn, 200)
    assert html =~ "Pick your"
    assert html =~ "Avatar"
    assert html =~ "randomize-button"
  end

  test "create as guest", %{conn: conn} do
    skills = Enum.map(base_skills(), fn skill -> skill.id end)
    avatar = base_avatar().id

    conn = conn |> get("/start") |> recycle() |> post("/start", %{"skills" => skills, "avatar" => avatar})

    assert "/training" = redirected_to(conn, 302)
    assert get_session(conn, :player_id)
  end

  test "preview bookmarks redirect permanently and preserve queries and tokens", %{conn: conn} do
    for path <- [
          "",
          "/",
          "/base",
          "/start",
          "/arena/edit",
          "/battles/42",
          "/matches/42",
          "/users/reset_password/token",
          "/users/settings/confirm_email/token"
        ] do
      destination = if path in ["", "/"], do: "/", else: path
      response = get(conn, "/new" <> path <> "?source=bookmark&tab=skins")
      assert redirected_to(response, 301) == destination <> "?source=bookmark&tab=skins"
    end
  end

  test "an already-open preview guest form creates a hero on the canonical routes", %{conn: conn} do
    response =
      conn
      |> get("/start")
      |> recycle()
      |> post("/new/start", %{"skills" => Enum.map(base_skills(), & &1.id), "avatar" => base_avatar().id})

    assert redirected_to(response) == "/training"
    assert get_session(response, :player_id)
  end
end
