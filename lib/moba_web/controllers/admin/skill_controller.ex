defmodule MobaWeb.Admin.SkillController do
  use MobaWeb, :controller

  alias Moba.Admin
  alias Moba.Game.Schema.Skill
  import Ecto.Query, warn: false

  plug(:put_layout, {MobaWeb.LayoutView, "torch.html"})

  def index(conn, params) do
    case Admin.paginate_skills(params) do
      {:ok, assigns} ->
        render(conn, "index.html", assigns)

      error ->
        conn
        |> put_flash(:error, "There was an error rendering Skills. #{inspect(error)}")
        |> redirect(to: Routes.skill_path(conn, :index))
    end
  end

  def root(conn, _) do
    redirect(conn, to: "/admin/matches/current")
  end

  def new(conn, _params) do
    changeset = Admin.change_skill(%Skill{})
    render(conn, "new.html", changeset: changeset, skills: [])
  end

  def create(conn, %{"skill" => skill_params}) do
    case Admin.create_skill(skill_params) do
      {:ok, skill} ->
        conn
        |> put_flash(:info, "Skill created successfully.")
        |> redirect(to: Routes.skill_path(conn, :show, skill))

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, "new.html", changeset: changeset)
    end
  end

  def show(conn, %{"id" => id}) do
    skill = Admin.get_skill!(id)
    render(conn, "show.html", skill: skill)
  end

  def edit(conn, %{"id" => id}) do
    skill = Admin.get_skill!(id)
    changeset = Admin.change_skill(skill)

    skills = Admin.skills_with_same_code(skill.code)

    render(conn, "edit.html", skill: skill, changeset: changeset, skills: skills)
  end

  def update(conn, %{"id" => id, "skill" => skill_params}) do
    skill = Admin.get_skill!(id)

    case Admin.update_skill(skill, skill_params) do
      {:ok, skill} ->
        conn
        |> put_flash(:info, "Skill updated successfully.")
        |> redirect(to: Routes.skill_path(conn, :show, skill))

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, "edit.html", skill: skill, changeset: changeset)
    end
  end

  def delete(conn, %{"id" => id}) do
    skill = Admin.get_skill!(id)
    {:ok, _skill} = Admin.delete_skill(skill)

    conn
    |> put_flash(:info, "Skill deleted successfully.")
    |> redirect(to: Routes.skill_path(conn, :index))
  end
end
