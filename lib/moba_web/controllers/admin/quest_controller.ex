defmodule MobaWeb.Admin.QuestController do
  use MobaWeb, :controller

  alias Moba.Admin
  alias Moba.Game.Schema.Quest

  plug(:put_layout, {MobaWeb.LayoutView, "torch.html"})

  def index(conn, params) do
    case Admin.paginate_quests(params) do
      {:ok, assigns} ->
        render(conn, "index.html", assigns)

      error ->
        conn
        |> put_flash(:error, "There was an error rendering Quests. #{inspect(error)}")
        |> redirect(to: Routes.quest_path(conn, :index))
    end
  end

  def new(conn, _params) do
    changeset = Admin.change_quest(%Quest{})
    render(conn, "new.html", changeset: changeset)
  end

  def create(conn, %{"quest" => quest_params}) do
    {:ok, quest} = Admin.create_quest(quest_params)

    conn
    |> put_flash(:info, "Quest created successfully.")
    |> redirect(to: Routes.quest_path(conn, :show, quest))
  end

  def show(conn, %{"id" => id}) do
    quest = Admin.get_quest!(id)
    render(conn, "show.html", quest: quest)
  end

  def edit(conn, %{"id" => id}) do
    quest = Admin.get_quest!(id)
    changeset = Admin.change_quest(quest)
    render(conn, "edit.html", quest: quest, changeset: changeset)
  end

  def update(conn, %{"id" => id, "quest" => quest_params}) do
    quest = Admin.get_quest!(id)

    case Admin.update_quest(quest, quest_params) do
      {:ok, quest} ->
        conn
        |> put_flash(:info, "Quest updated successfully.")
        |> redirect(to: Routes.quest_path(conn, :show, quest))

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, "edit.html", quest: quest, changeset: changeset)
    end
  end

  def delete(conn, %{"id" => id}) do
    quest = Admin.get_quest!(id)
    {:ok, _quest} = Admin.delete_quest(quest)

    conn
    |> put_flash(:info, "Quest deleted successfully.")
    |> redirect(to: Routes.quest_path(conn, :index))
  end
end
