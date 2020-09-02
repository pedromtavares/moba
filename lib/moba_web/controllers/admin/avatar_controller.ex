defmodule MobaWeb.Admin.AvatarController do
  use MobaWeb, :controller

  alias Moba.Admin
  alias Moba.Game.Schema.Avatar

  plug(:put_layout, {MobaWeb.LayoutView, "torch.html"})

  def index(conn, params) do
    case Admin.paginate_avatars(params) do
      {:ok, assigns} ->
        render(conn, "index.html", assigns)

      error ->
        conn
        |> put_flash(:error, "There was an error rendering Avatars. #{inspect(error)}")
        |> redirect(to: Routes.avatar_path(conn, :index))
    end
  end

  def new(conn, _params) do
    changeset = Admin.change_avatar(%Avatar{})
    render(conn, "new.html", changeset: changeset)
  end

  def create(conn, %{"avatar" => avatar_params}) do
    avatar = Admin.create_avatar(avatar_params)

    conn
    |> put_flash(:info, "Avatar created successfully.")
    |> redirect(to: Routes.avatar_path(conn, :show, avatar))
  end

  def show(conn, %{"id" => id}) do
    avatar = Admin.get_avatar!(id)
    render(conn, "show.html", avatar: avatar)
  end

  def edit(conn, %{"id" => id}) do
    avatar = Admin.get_avatar!(id)
    changeset = Admin.change_avatar(avatar)
    render(conn, "edit.html", avatar: avatar, changeset: changeset)
  end

  def update(conn, %{"id" => id, "avatar" => avatar_params}) do
    avatar = Admin.get_avatar!(id)

    case Admin.update_avatar(avatar, avatar_params) do
      {:ok, avatar} ->
        conn
        |> put_flash(:info, "Avatar updated successfully.")
        |> redirect(to: Routes.avatar_path(conn, :show, avatar))

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, "edit.html", avatar: avatar, changeset: changeset)
    end
  end

  def delete(conn, %{"id" => id}) do
    avatar = Admin.get_avatar!(id)
    {:ok, _avatar} = Admin.delete_avatar(avatar)

    conn
    |> put_flash(:info, "Avatar deleted successfully.")
    |> redirect(to: Routes.avatar_path(conn, :index))
  end
end
