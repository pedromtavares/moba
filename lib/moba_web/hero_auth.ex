defmodule MobaWeb.HeroAuth do
  @moduledoc """
  Plug used to make sure a current hero exists and is in the correct game mode
  """

  import Plug.Conn
  import Phoenix.Controller

  alias Moba.Game

  def init(_) do
  end

  def call(conn, _) do
    user = conn.assigns.current_user
    mode = get_session(conn, :current_mode) || "pve"
    hero = Game.current_hero(user, mode)
    last_hero = Game.last_pvp_hero(user.id)

    cond do
      hero ->
        conn
        |> assign(:current_hero, hero)
        |> put_session(:hero_id, hero.id)

      last_hero ->
        conn
        |> assign(:current_hero, nil)
        |> put_session(:hero_id, nil)
        |> redirect(to: "/match")
        |> halt()

      true ->
        conn
        |> assign(:current_hero, nil)
        |> put_session(:hero_id, nil)
        |> redirect(to: "/join")
        |> halt()
    end
  end
end
