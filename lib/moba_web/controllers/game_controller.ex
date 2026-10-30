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
        redirect(conn, to: preview_path(conn, ~p"/arena"))

      hero && is_nil(hero.finished_at) ->
        redirect(conn, to: preview_path(conn, ~p"/training"))

      player ->
        redirect(conn, to: preview_path(conn, ~p"/base"))

      true ->
        counts = %{
          players: format_number(Admin.players_count()),
          heroes: format_number(Admin.heroes_count()),
          matches: format_number(Admin.matches_count())
        }

        conn
        |> assign(:counts, counts)
        |> assign(:preview, true)
        |> render(:homepage, layout: false)
    end
  end

  def redirect_preview(conn, _params) do
    path = preview_path(conn, conn.request_path)
    path = if conn.query_string == "", do: path, else: path <> "?" <> conn.query_string
    conn |> put_status(:moved_permanently) |> redirect(to: path)
  end

  def create(conn, %{"skills" => selected_skills, "avatar" => selected_avatar}) do
    cond do
      get_session(conn, :player_id) || conn.assigns.current_user ->
        redirect(conn, to: preview_path(conn, ~p"/"))

      session_key = get_session(conn, :cache_key) ->
        avatar = Game.get_avatar!(selected_avatar)
        skills = Game.list_chosen_skills(selected_skills)
        player = Game.start_guest!(session_key, avatar, skills)

        if player.user_id do
          redirect(conn, to: preview_path(conn, ~p"/users/log_in"))
        else
          path =
            if player.current_pve_hero && is_nil(player.current_pve_hero.finished_at),
              do: ~p"/training",
              else: ~p"/base"

          conn
          |> put_session(:player_id, player.id)
          |> redirect(to: preview_path(conn, path))
        end

      true ->
        redirect(conn, to: preview_path(conn, ~p"/start"))
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
