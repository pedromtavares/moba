defmodule MobaWeb.Admin.SkinController do
  use MobaWeb, :controller

  alias Moba.Admin
  alias Moba.Game.Schema.Skin

  plug(:put_layout, {MobaWeb.LayoutView, "torch.html"})

  def index(conn, params) do
    case Admin.paginate_skins(params) do
      {:ok, assigns} ->
        render(conn, "index.html", assigns)

      error ->
        conn
        |> put_flash(:error, "There was an error rendering Skins. #{inspect(error)}")
        |> redirect(to: Routes.skin_path(conn, :index))
    end
  end

  def new(conn, _params) do
    changeset = Admin.change_skin(%Skin{})
    render(conn, "new.html", changeset: changeset)
  end

  def create(conn, %{"skin" => skin_params}) do
    {:ok, skin} = Admin.create_skin(skin_params)

    conn
    |> put_flash(:info, "Skin created successfully.")
    |> redirect(to: Routes.skin_path(conn, :show, skin))
  end

  def show(conn, %{"id" => id}) do
    skin = Admin.get_skin!(id)
    render(conn, "show.html", skin: skin)
  end

  def edit(conn, %{"id" => id}) do
    skin = Admin.get_skin!(id)
    changeset = Admin.change_skin(skin)
    render(conn, "edit.html", skin: skin, changeset: changeset)
  end

  def update(conn, %{"id" => id, "skin" => skin_params}) do
    skin = Admin.get_skin!(id)

    case Admin.update_skin(skin, skin_params) do
      {:ok, skin} ->
        conn
        |> put_flash(:info, "Skin updated successfully.")
        |> redirect(to: Routes.skin_path(conn, :show, skin))

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, "edit.html", skin: skin, changeset: changeset)
    end
  end

  def delete(conn, %{"id" => id}) do
    skin = Admin.get_skin!(id)
    {:ok, _skin} = Admin.delete_skin(skin)

    conn
    |> put_flash(:info, "Skin deleted successfully.")
    |> redirect(to: Routes.skin_path(conn, :index))
  end
end
