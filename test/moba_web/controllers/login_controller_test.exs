defmodule MobaWeb.LoginControllerTest do
  use MobaWeb.ConnCase

  test "loads", %{conn: conn} do
    conn = get(conn, "/session/new")
    assert html_response(conn, 200) =~ "Sign In to Browser MOBA"
  end

  test "create", %{conn: conn} do
    user = create_user()
    conn = post(conn, "/session", %{"user" => %{email: user.email, password: "123456"}})
    assert "/" = redirected_to(conn, 302)
  end
end
