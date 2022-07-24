defmodule MobaWeb.GameController do
  alias Moba.Game
  use MobaWeb, :controller

  def index(conn, _params) do
    user = conn.assigns.current_user
    player_id = get_session(conn, :player_id)

    player =
      cond do
        player_id -> Game.get_player!(player_id)
        user -> Moba.player_for(user)
        true -> nil
      end

    hero = player && player.current_pve_hero

    cond do
      player && player.tutorial_step == 30 -> redirect(conn, to: "/arena")
      hero && is_nil(hero.finished_at) -> redirect(conn, to: "/training")
      player -> redirect(conn, to: "/base")
      true -> render(conn, "homepage.html", layout: {MobaWeb.LayoutView, "homepage.html"})
    end
  end

  def start(conn, _params) do
    conn =
      if get_session(conn, :cache_key) do
        conn
      else
        put_session(conn, :cache_key, UUID.uuid1())
      end

    live_render(conn, MobaWeb.CreateLive,
      session: %{"token" => get_csrf_token(), "cache_key" => get_session(conn, :cache_key)}
    )
  end

  def create(conn, %{"skills" => selected_skills, "avatar" => selected_avatar}) do
    player = Game.create_player!(%{})
    avatar = Game.get_avatar!(selected_avatar)
    skills = Game.list_chosen_skills(selected_skills)

    Game.create_current_pve_hero!(%{name: avatar.name}, player, avatar, skills)

    conn
    |> put_session(:player_id, player.id)
    |> redirect(to: "/training")
  end
end
