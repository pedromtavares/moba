defmodule MobaWeb.ReturnControllerTest do
  use MobaWeb.ConnCase, async: true

  import Moba.AccountsFixtures
  alias Moba.{Accounts.ReturnCampaign, Accounts.UserToken, Repo}

  setup do
    user = user_fixture()
    player = create_player!(%{pvp_points: 10}, user)
    path = Path.join(System.tmp_dir!(), "moba-return-#{System.unique_integer([:positive])}.json")
    on_exit(fn -> File.rm(path) end)
    {:ok, _} = ReturnCampaign.prepare(path, issue_tokens: true)
    payload = path |> File.read!() |> Jason.decode!()
    contact = Enum.find(payload["contacts"], &(&1["user_id"] == user.id))
    token = contact["return_url"] |> URI.parse() |> Map.fetch!(:fragment) |> URI.decode_query() |> Map.fetch!("token")
    %{user: user, player: player, token: token}
  end

  test "GET shows the landing artwork without consuming an invitation", %{conn: conn, token: token} do
    conn = get(conn, ~p"/return")
    document = conn |> html_response(200) |> LazyHTML.from_document()
    assert LazyHTML.query(document, "#return-enter[disabled]") |> LazyHTML.text() == "Enter Game"

    assert LazyHTML.query(document, ".landing-artwork img") |> LazyHTML.attribute("src") ==
             ["/images/landing/home-heroes-v5.png"]

    refute get_session(conn, :user_token)
    assert {:ok, _} = ReturnCampaign.preview(token)
    assert get_resp_header(conn, "cache-control") == ["no-store"]
    assert get_resp_header(conn, "referrer-policy") == ["no-referrer"]
    assert get_resp_header(conn, "x-robots-tag") == ["noindex, nofollow"]
  end

  test "preview returns the username but does not log in or use the token", %{conn: conn, token: token, user: user} do
    conn = post(conn, ~p"/return/check", %{token: token})
    assert json_response(conn, 200) == %{"username" => user.username}
    refute get_session(conn, :user_token)
    assert {:ok, _} = ReturnCampaign.preview(token)
  end

  test "Enter Game consumes the invitation and replaces an unrelated player session", context do
    %{conn: conn, token: token, user: user, player: player} = context
    other = user_fixture()
    other_player = create_player!(%{}, other)

    conn =
      conn
      |> log_in_user(other)
      |> put_session(:player_id, other_player.id)
      |> put_session(:user_return_to, "/admin")
      |> post(~p"/return", %{token: token})

    assert redirected_to(conn) == ~p"/base"
    assert get_session(conn, :player_id) == player.id
    assert Accounts.get_user_by_session_token(get_session(conn, :user_token)).id == user.id
    assert conn.resp_cookies["_moba_web_user_remember_me"]
    assert :error = ReturnCampaign.preview(token)

    assert conn |> recycle() |> post(~p"/return", %{token: token}) |> html_response(422) =~
             "Your invitation has expired."
  end

  test "invalid inputs fail gracefully without authentication", %{conn: conn} do
    for token <- ["invalid", %{}, ["bad"]] do
      check = post(conn, ~p"/return/check", %{token: token})
      assert json_response(check, 422) == %{"error" => "invalid_invitation"}
      response = post(conn, ~p"/return", %{token: token})
      document = response |> html_response(422) |> LazyHTML.from_document()
      assert LazyHTML.query(document, "#return-invitation-form[hidden]") |> Enum.count() == 1
      refute get_session(response, :user_token)
    end
  end

  test "posts without CSRF protection are rejected", %{conn: conn, token: token} do
    for path <- [~p"/return/check", ~p"/return"] do
      assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
        conn |> put_private(:plug_skip_csrf_protection, false) |> post(path, %{token: token})
      end
    end

    assert {:ok, _} = ReturnCampaign.preview(token)
  end

  test "tokens are omitted from request error context and filtered in Phoenix logs", %{conn: conn, token: token} do
    for path <- ["/return", "/return/check"] do
      request = %{conn | request_path: path, params: %{"token" => token}}
      assert MobaWeb.SentryScrubber.body(request) == %{}
    end

    assert Phoenix.Logger.filter_values(%{"token" => token}) == %{"token" => "[FILTERED]"}
    assert Repo.get_by(UserToken, token: token) == nil
  end
end
