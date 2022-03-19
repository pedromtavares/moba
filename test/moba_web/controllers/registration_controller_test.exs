defmodule MobaWeb.RegistrationControllerTest do
  use MobaWeb.ConnCase

  test "loads without guest", %{conn: conn} do
    conn = get(conn, "/registration/new")
    assert html_response(conn, 200) =~ "One last step"
  end

  test "loads with guest", %{conn: conn} do
    guest = create_guest()
    create_base_hero(%{}, guest)

    conn = init_test_session(conn, guest_user_id: guest.id) |> get("/registration/new")
    assert html_response(conn, 200) =~ "Skill Build"
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

    assert "/training" = redirected_to(conn, 302)
  end

  test "create with guest", %{conn: conn} do
    guest = create_guest()
    hero = create_base_hero(%{}, guest)

    conn =
      init_test_session(conn, guest_user_id: guest.id)
      |> post("/registration", %{
        "user" => %{
          email: "test@test.com",
          username: "someonetest",
          password: "123456",
          password_confirmation: "123456"
        }
      })

    assert "/training" = redirected_to(conn, 302)

    hero = Game.get_hero!(hero.id)

    assert hero.name == "someonetest"
    refute hero.user_id == guest.id
  end
end
