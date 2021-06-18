defmodule MobaWeb.Admin.MatchController do
  use MobaWeb, :controller

  alias Moba.Admin

  plug(:put_layout, {MobaWeb.LayoutView, "admin.html"})

  def index(conn, params) do
    case Admin.paginate_matches(params) do
      {:ok, assigns} ->
        render(conn, "index.html", assigns)

      error ->
        conn
        |> put_flash(:error, "There was an error rendering matches. #{inspect(error)}")
        |> redirect(to: Routes.match_path(conn, :index))
    end
  end

  def show(conn, %{"id" => id}), do: live_render(conn, MobaWeb.Admin.MatchLiveView, session: %{"match_id" => id})

  def edit(conn, %{"id" => id}) do
    match = Admin.get_match!(id)
    changeset = Admin.change_match(match)
    render(conn, "edit.html", match: match, changeset: changeset)
  end

  def update(conn, %{"id" => id, "match" => match_params}) do
    match = Admin.get_match!(id)

    case Admin.update_match(match, match_params) do
      {:ok, match} ->
        conn
        |> put_flash(:info, "match updated successfully.")
        |> redirect(to: Routes.match_path(conn, :show, match))

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, "edit.html", match: match, changeset: changeset)
    end
  end
end
