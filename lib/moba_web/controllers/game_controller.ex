defmodule MobaWeb.GameController do
  alias Moba.{Game, Accounts}
  use MobaWeb, :controller

  def index(conn, _params) do
    user = conn.assigns.current_user

    cond do
      user && Game.current_pve_hero(user) -> redirect(conn, to: "/jungle")
      user -> redirect(conn, to: "/base")
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

    live_render(conn, MobaWeb.CreateLiveView,
      session: %{"token" => get_csrf_token(), "cache_key" => get_session(conn, :cache_key)}
    )
  end

  def create(conn, %{"skills" => selected_skills, "avatar" => selected_avatar}) do
    {user, conn} = Accounts.create_guest(conn)
    avatar = Game.get_avatar!(selected_avatar)
    skills = Game.list_chosen_skills(selected_skills)

    Moba.create_current_pve_hero!(%{name: avatar.name}, user, avatar, skills)

    conn
    |> put_session(:guest_user_id, user.id)
    |> redirect(to: "/jungle")
  end
end
