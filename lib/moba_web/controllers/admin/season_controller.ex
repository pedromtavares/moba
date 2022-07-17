defmodule MobaWeb.Admin.SeasonController do
  use MobaWeb, :controller

  alias Moba.Admin

  plug(:put_layout, {MobaWeb.LayoutView, "admin.html"})

  def index(conn, params) do
    case Admin.paginate_seasons(params) do
      {:ok, assigns} ->
        render(conn, "index.html", assigns)

      error ->
        conn
        |> put_flash(:error, "There was an error rendering seasons. #{inspect(error)}")
        |> redirect(to: Routes.season_path(conn, :index))
    end
  end

  def show(conn, %{"id" => id}), do: live_render(conn, MobaWeb.Admin.SeasonLiveView, session: %{"season_id" => id})

  def edit(conn, %{"id" => id}) do
    season = Admin.get_season!(id)
    changeset = Admin.change_season(season)
    render(conn, "edit.html", season: season, changeset: changeset)
  end

  def update(conn, %{"id" => id, "season" => season_params}) do
    season = Admin.get_season!(id)

    case Admin.update_season(season, season_params) do
      {:ok, season} ->
        conn
        |> put_flash(:info, "Season updated successfully.")
        |> redirect(to: Routes.season_path(conn, :show, season))

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, "edit.html", season: season, changeset: changeset)
    end
  end
end
