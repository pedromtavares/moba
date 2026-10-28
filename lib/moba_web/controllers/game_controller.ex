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
        |> assign(
          :landing_background,
          Moba.Image.url({%{file_name: "home-heroes-v5.png", updated_at: nil}, %{code: "landing"}})
        )
        |> assign(
          :landing_mobile_background,
          Moba.Image.url({%{file_name: "home-heroes-mobile-v1.webp", updated_at: nil}, %{code: "landing"}})
        )
        |> render(:homepage, layout: false)
    end
  end

  def create(conn, %{"skills" => selected_skills, "avatar" => selected_avatar}) do
    cond do
      get_session(conn, :player_id) || conn.assigns.current_user ->
        redirect(conn, to: ~p"/")

      session_key = get_session(conn, :cache_key) ->
        avatar = Game.get_avatar!(selected_avatar)
        skills = Game.list_chosen_skills(selected_skills)
        player = Game.start_guest!(session_key, avatar, skills)

        if player.user_id do
          redirect(conn, to: ~p"/users/log_in")
        else
          path =
            if player.current_pve_hero && is_nil(player.current_pve_hero.finished_at),
              do: ~p"/training",
              else: ~p"/base"

          conn
          |> put_session(:player_id, player.id)
          |> redirect(to: path)
        end

      true ->
        redirect(conn, to: ~p"/start")
    end
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
