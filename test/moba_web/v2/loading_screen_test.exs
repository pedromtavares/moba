defmodule MobaWeb.V2.LoadingScreenTest do
  use MobaWeb.ConnCase

  test "registered players get one persistent loading screen alongside the sidebar", %{conn: conn} do
    hero = create_base_hero()
    finished = create_base_hero(%{finished_at: Timex.now()}, Game.get_player!(hero.player_id))
    Game.update_hero_collection!(finished)
    conn = conn |> log_in_user(hero.player.user) |> put_session(:player_id, hero.player_id)

    for path <- ["/base", "/arena", "/player/#{hero.player_id}", "/community", "/tavern", "/library", "/users/settings"] do
      document = conn |> get(path) |> html_response(200) |> LazyHTML.from_document()
      assert Enum.count(LazyHTML.query(document, "#game-loading-screen[hidden][role=status]")) == 1, path
      assert Enum.count(LazyHTML.query(document, "#game-loading-icon[src='/images/navigation/profile.webp']")) == 1
      assert Enum.count(LazyHTML.query(document, "#game-loading-progress[role=progressbar]")) == 1
      assert Enum.empty?(LazyHTML.query(document, "[data-phx-main] #game-loading-screen"))

      if path != "/users/settings" do
        assert Enum.count(LazyHTML.query(document, "#game-sidebar")) == 1, path
      end
    end
  end

  test "guests do not get an authenticated loading screen", %{conn: conn} do
    document = conn |> get("/start") |> html_response(200) |> LazyHTML.from_document()
    assert Enum.empty?(LazyHTML.query(document, "#game-loading-screen"))
  end
end
