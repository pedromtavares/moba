defmodule MobaWeb.LibraryLiveView do
  use MobaWeb, :live_view

  def mount(_, _session, socket) do
    avatars = Game.list_avatars()
    ultimates = Game.list_ultimate_skills()

    normals =
      Game.list_normal_skills()
      |> Enum.group_by(fn skill -> skill.code end)

    {:ok, assign(socket, avatars: avatars, ultimates: ultimates, skills: normals, sidebar_code: "library")}
  end

  def render(assigns) do
    MobaWeb.LibraryView.render("index.html", assigns)
  end
end
