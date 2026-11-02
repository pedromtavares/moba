defmodule MobaWeb.GuestAccountSessionTest do
  use MobaWeb.ConnCase

  import Moba.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Moba.Repo
  alias MobaWeb.V2.Hooks.RequireAuth

  test "signing in after guest combat switches to the account without adopting or losing the guest", %{conn: conn} do
    guest_conn = conn |> get("/start") |> recycle() |> post("/start", guest_params())
    guest_id = get_session(guest_conn, :player_id)
    guest = Game.get_player!(guest_id)
    hero = Game.update_hero!(guest.current_pve_hero, %{total_hp: 100_000})
    target = Game.list_targets(hero) |> hd() |> then(&Game.get_target!(&1.id))
    battle = Game.start_pve_battle!(target)
    battle = Engine.continue_battle!(battle, %{skill: nil, item: nil, player_id: guest_id})
    assert battle.turns != []

    user = user_fixture()
    account_hero = create_base_hero(%{}, Moba.player_for(user))

    response =
      guest_conn
      |> recycle()
      |> post("/users/log_in", %{"user" => %{"email" => user.email, "password" => valid_user_password()}})

    assert redirected_to(response) == "/base"
    assert get_session(response, :player_id) == account_hero.player_id
    assert Accounts.get_user_by_session_token(get_session(response, :user_token)).id == user.id

    {:ok, view, _} = response |> recycle() |> live("/training")
    assert has_element?(view, "#hero-bar .hero-name", account_hero.name)
    refute has_element?(view, "#hero-bar .hero-name", hero.name)

    assert Repo.get!(Game.Schema.Player, guest_id).user_id == nil
    assert Game.get_player!(guest_id).current_pve_hero_id == hero.id
    assert Enum.map(Engine.get_battle!(battle.id).turns, & &1.id) == Enum.map(battle.turns, & &1.id)

    logout = response |> recycle() |> delete("/users/log_out")
    refute get_session(logout, :user_token)
    refute get_session(logout, :player_id)
    {:ok, signup, _} = logout |> recycle() |> live("/users/register")
    assert has_element?(signup, "#registration_form")
  end

  test "failed sign-in leaves the guest playable", %{conn: conn} do
    guest_conn = conn |> get("/start") |> recycle() |> post("/start", guest_params())
    guest_id = get_session(guest_conn, :player_id)

    response =
      guest_conn
      |> recycle()
      |> post("/users/log_in", %{"user" => %{"email" => "unknown@example.com", "password" => "incorrect"}})

    assert redirected_to(response) == "/users/log_in"
    assert get_session(response, :player_id) == guest_id
    refute get_session(response, :user_token)
    {:ok, view, _} = response |> recycle() |> live("/training")
    assert has_element?(view, "#hero-bar .hero-name", Game.get_player!(guest_id).current_pve_hero.name)
  end

  test "old mixed sessions recover on both the root and protected game pages", %{conn: conn} do
    guest = guest_player()
    user = user_fixture()
    account = Moba.player_for(user)
    mixed = conn |> log_in_user(user) |> put_session(:player_id, guest.id)

    root = get(mixed, "/")
    assert redirected_to(root) == "/base"
    assert get_session(root, :player_id) == account.id

    response = get(mixed, "/base")
    assert html_response(response, 200)
    assert response.assigns.current_player.id == account.id
    assert get_session(response, :player_id) == account.id

    {:ok, profile, _} = response |> recycle() |> live("/user/#{user.id}")
    assert has_element?(profile, "a[data-method='delete'][href='/users/log_out']")
    refute has_element?(profile, "#create-account-link")
    assert Repo.get!(Game.Schema.Player, guest.id).user_id == nil
  end

  test "an authenticated registration redirect repairs the guest session first", %{conn: conn} do
    guest = guest_player()
    user = user_fixture()

    response = conn |> log_in_user(user) |> put_session(:player_id, guest.id) |> get("/users/register")
    assert redirected_to(response) == "/base"
    assert get_session(response, :player_id) == Moba.player_for(user).id
    assert response |> recycle() |> get("/base") |> html_response(200)
  end

  test "logging out of a previously mixed session clears both identities", %{conn: conn} do
    guest = guest_player()
    user = user_fixture()

    response = conn |> log_in_user(user) |> put_session(:player_id, guest.id) |> delete("/users/log_out")
    assert redirected_to(response) == "/"
    refute get_session(response, :user_token)
    refute get_session(response, :player_id)
    assert response |> recycle() |> get("/users/register") |> html_response(200)
  end

  test "stale LiveView sessions never mount a guest or another player for a signed-in account" do
    user = user_fixture()
    token = Accounts.generate_user_session_token(user)
    guest = guest_player()
    other = create_player!()

    for player_id <- [guest.id, other.id, nil] do
      socket = %Phoenix.LiveView.Socket{endpoint: MobaWeb.Endpoint, assigns: %{__changed__: %{}, flash: %{}}}
      session = %{"player_id" => player_id, "user_token" => token}
      assert {:halt, socket} = RequireAuth.on_mount(:default, %{}, session, socket)
      assert socket.redirected == {:redirect, %{to: "/base", status: 302}}
      refute Map.has_key?(socket.assigns, :current_player)
    end
  end

  defp guest_params, do: %{"avatar" => base_avatar().id, "skills" => Enum.map(creation_skills(), & &1.id)}

  defp guest_player do
    Game.start_guest!("guest-login-#{System.unique_integer([:positive])}", base_avatar(), creation_skills())
  end
end
