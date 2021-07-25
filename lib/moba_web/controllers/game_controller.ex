defmodule MobaWeb.GameController do
  alias Moba.{Game, Accounts}
  use MobaWeb, :controller

  def index(conn, _params) do
    user = conn.assigns.current_user

    if user do
      if user.current_pvp_hero_id do
        conn
        |> put_session(:current_mode, "pvp")
        |> redirect(to: "/arena")
      else
        conn
        |> put_session(:current_mode, "pve")
        |> redirect(to: "/jungle")
      end
    else
      render(conn, "homepage.html", layout: {MobaWeb.LayoutView, "homepage.html"})
    end
  end

  def start(conn, _params) do
    conn =
      if get_session(conn, :cache_key) do
        conn
      else
        put_session(conn, :cache_key, UUID.uuid1())
      end

    conn
    |> live_render(MobaWeb.CreateLiveView,
      session: %{"token" => get_csrf_token(), "cache_key" => get_session(conn, :cache_key)}
    )
  end

  def create(conn, %{"skills" => selected_skills, "avatar" => selected_avatar}) do
    {user, conn} = Accounts.create_guest(conn)
    avatar = Game.get_avatar!(selected_avatar)
    skills = Game.list_chosen_skills(selected_skills)

    Moba.create_current_pve_hero!(%{name: avatar.name, easy_mode: true}, user, avatar, skills)

    conn
    |> put_session(:guest_user_id, user.id)
    |> redirect(to: "/game/pve")
  end

  def switch_mode(conn, %{"mode" => mode}) when mode in ["pve", "pvp"] do
    path = if mode == "pve", do: "/jungle", else: "/arena"

    conn
    |> put_session(:current_mode, mode)
    |> redirect(to: path)
  end

  def join(conn, _) do
    mode = get_session(conn, :current_mode)

    path = if mode == "pvp", do: "/arena/select", else: "/create"

    conn
    |> redirect(to: path)
  end
end
