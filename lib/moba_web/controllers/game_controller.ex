defmodule MobaWeb.GameController do
  alias Moba.{Admin, Game}
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
      player && player.tutorial_step == 30 ->
        redirect(conn, to: ~p"/arena")

      hero && is_nil(hero.finished_at) ->
        redirect(conn, to: ~p"/training")

      player ->
        redirect(conn, to: ~p"/base")

      true ->
        counts = %{
          players: format_number(Admin.players_count()),
          heroes: format_number(Admin.heroes_count()),
          matches: format_number(Admin.matches_count())
        }

        conn
        |> assign(:counts, counts)
        |> render(:homepage, layout: false)
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
    |> redirect(to: ~p"/training")
  end

  defp format_number(n) do
    "#{n}"
    |> to_charlist()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.map(&Enum.reverse(&1))
    |> Enum.reverse()
    |> Enum.join(",")
  end
end
