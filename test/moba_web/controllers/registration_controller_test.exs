defmodule MobaWeb.RegistrationControllerTest do
  use MobaWeb.ConnCase

  test "loads without guest", %{conn: conn} do
    conn = get(conn, "/registration/new")
    assert html_response(conn, 200) =~ "Create an account"
  end

  test "loads with guest", %{conn: conn} do
    player = create_player!()
    create_base_hero(%{}, player)

    conn = init_test_session(conn, player_id: player.id) |> get("/registration/new")
    assert html_response(conn, 200) =~ "Create an account"
  end

  test "create without guest", %{conn: conn} do
    conn =
      post(conn, "/registration", %{
        "user" => %{
          email: "test@test.com",
          username: "someonetest",
          password: "123456",
          password_confirmation: "123456"
        }
      })

    assert "/" = redirected_to(conn, 302)
  end

  test "create with guest", %{conn: conn} do
    player = create_player!()
    hero = create_base_hero(%{}, player)

    conn =
      init_test_session(conn, player_id: player.id)
      |> post("/registration", %{
        "user" => %{
          email: "test@test.com",
          username: "someonetest",
          password: "123456",
          password_confirmation: "123456"
        }
      })

    assert "/" = redirected_to(conn, 302)

    hero = Game.get_hero!(hero.id)

    assert hero.name == "someonetest"
  end
end
