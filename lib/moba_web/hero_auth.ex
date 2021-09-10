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

    cond do
      hero ->
        conn
        |> assign(:current_hero, hero)
        |> put_session(:hero_id, hero.id)

      mode == "pvp" ->
        conn
        |> redirect(to: "/arena/select")
        |> halt()

      true ->
        conn
        |> assign(:current_hero, nil)
        |> put_session(:hero_id, nil)
        |> redirect(to: "/base")
        |> halt()
    end
  end
end
