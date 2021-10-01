defmodule MobaWeb.GameController do
  alias Moba.{Game, Accounts}
  use MobaWeb, :controller

  def index(conn, _params) do
    user = conn.assigns.current_user

    if user do
      conn
      |> redirect(to: "/base")
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

    live_render(conn, MobaWeb.CreateLiveView,
      session: %{"token" => get_csrf_token(), "cache_key" => get_session(conn, :cache_key)}
    )
  end

  def summon(conn, _params) do
    live_render(conn, MobaWeb.CreateLiveView, session: %{"summon" => true})
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

  def switch_mode(conn, _), do: redirect(conn, to: "/base")

  def continue(conn, %{"hero_id" => hero_id}) do
    hero = Game.get_hero!(hero_id)
    user = conn.assigns.current_user

    if hero.user_id == user.id do
      Accounts.set_current_pve_hero!(user, hero_id)

      conn
      |> put_session(:current_mode, "pve")
      |> redirect(to: "/jungle")
    else
      conn
      |> redirect(to: "/base")
    end
  end
end
