defmodule MobaWeb.GuestCreationTest do
  use MobaWeb.ConnCase
  import Phoenix.LiveViewTest

  alias Moba.Repo
  alias Moba.Game.Schema.{Hero, Player}

  test "replayed submissions from the same pre-response session create one guest and hero", %{conn: conn} do
    session = conn |> get("/start") |> recycle()
    counts = {Repo.aggregate(Player, :count), Repo.aggregate(Hero, :count)}

    first = post(session, "/start", build_params())
    retry = post(session, "/start", build_params())

    assert redirected_to(first) == "/training"
    assert redirected_to(retry) == "/training"
    assert get_session(first, :player_id) == get_session(retry, :player_id)
    assert {Repo.aggregate(Player, :count), Repo.aggregate(Hero, :count)} == {elem(counts, 0) + 1, elem(counts, 1) + 1}
  end

  test "an existing guest session cannot create another player by reposting /start", %{conn: conn} do
    first = conn |> get("/start") |> recycle() |> post("/start", build_params())
    player_id = get_session(first, :player_id)
    hero_id = Game.get_player!(player_id).current_pve_hero_id
    counts = {Repo.aggregate(Player, :count), Repo.aggregate(Hero, :count)}

    retry = first |> recycle() |> post("/start", build_params())
    assert redirected_to(retry) == "/"
    assert get_session(retry, :player_id) == player_id
    assert Game.get_player!(player_id).current_pve_hero_id == hero_id
    assert {Repo.aggregate(Player, :count), Repo.aggregate(Hero, :count)} == counts
  end

  test "different guest sessions can deliberately choose the same build", %{conn: conn} do
    first = conn |> get("/start") |> recycle() |> post("/start", build_params())
    second = build_conn() |> get("/start") |> recycle() |> post("/start", build_params())
    refute get_session(first, :player_id) == get_session(second, :player_id)
  end

  test "a returning guest can invoke a new hero under the same player", %{conn: conn} do
    first = conn |> get("/start") |> recycle() |> post("/start", build_params())
    player_id = get_session(first, :player_id)
    original = Game.get_player!(player_id).current_pve_hero
    Game.archive_hero!(original)
    players = Repo.aggregate(Player, :count)

    {:ok, view, _} = first |> recycle() |> live("/invoke")
    avatar = base_avatar()
    render_click(view, "pick-avatar", %{"id" => avatar.id})
    render_click(view, "pick-build", %{"number" => "0"})
    assert has_element?(view, "#create-button[phx-click=create]")
    view |> element("#create-button") |> render_click()
    assert_redirect(view, "/training")

    player = Game.get_player!(player_id)
    refute player.current_pve_hero_id == original.id
    assert player.current_pve_hero.player_id == player_id
    assert Repo.aggregate(Player, :count) == players
  end

  test "a first-time guest still submits the normal signup form", %{conn: conn} do
    {:ok, view, _} = live(conn, "/start")
    render_click(view, "pick-avatar", %{"id" => base_avatar().id})
    render_click(view, "pick-build", %{"number" => "0"})
    assert has_element?(view, "form[action='/start'] #create-button[type=submit]")
    refute has_element?(view, "#create-button[phx-click=create]")
  end

  test "an old form restores the original guest session after its hero was archived", %{conn: conn} do
    session = conn |> get("/start") |> recycle()
    first = post(session, "/start", build_params())
    player_id = get_session(first, :player_id)
    Game.get_player!(player_id).current_pve_hero |> Game.archive_hero!()

    retry = post(session, "/start", build_params())
    assert redirected_to(retry) == "/base"
    assert get_session(retry, :player_id) == player_id
    assert is_nil(Game.get_player!(player_id).current_pve_hero_id)
  end

  test "a submission without an established start session returns to the picker", %{conn: conn} do
    players = Repo.aggregate(Player, :count)
    response = post(conn, "/start", build_params())
    assert redirected_to(response) == "/start"
    assert is_nil(get_session(response, :player_id))
    assert Repo.aggregate(Player, :count) == players
  end

  test "a logged-in user cannot create a guest by posting the guest form", %{conn: conn} do
    hero = create_base_hero()
    counts = {Repo.aggregate(Player, :count), Repo.aggregate(Hero, :count)}
    response = conn |> log_in_user(hero.player.user) |> post("/start", build_params())
    assert redirected_to(response) == "/"
    assert {Repo.aggregate(Player, :count), Repo.aggregate(Hero, :count)} == counts
  end

  test "an old anonymous form cannot restore a guest that has since become a registered account", %{conn: conn} do
    session = conn |> get("/start") |> recycle()
    first = post(session, "/start", build_params())
    player = Game.get_player!(get_session(first, :player_id))
    user = create_user()
    Game.update_player!(player, %{user_id: user.id})

    retry = post(session, "/start", build_params())
    assert redirected_to(retry) == "/users/log_in"
    assert is_nil(get_session(retry, :player_id))
  end

  defp build_params, do: %{"avatar" => base_avatar().id, "skills" => Enum.map(base_skills(), & &1.id)}
end
