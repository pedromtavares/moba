defmodule MobaWeb.HeroAuth do
  @moduledoc """
  Plug used to make sure a current hero exists
  """

  import Plug.Conn
  import Phoenix.Controller

  alias Moba.Game

  def init(_), do: nil

  def call(conn, _) do
    user = conn.assigns.current_user
    hero = Game.current_pve_hero(user)

    if hero do
      conn
      |> assign(:current_hero, hero)
      |> put_session(:hero_id, hero.id)
    else
      conn
      |> assign(:current_hero, nil)
      |> put_session(:hero_id, nil)
      |> redirect(to: "/base")
      |> halt()
    end
  end
end
