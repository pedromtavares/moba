defmodule MobaWeb.LibraryLive do
  use MobaWeb, :live_view

  def mount(_, _session, socket) do
    with socket = socket_init(socket) do
      {:ok, socket}
    end
  end

  def render(assigns) do
    MobaWeb.LibraryView.render("index.html", assigns)
  end

  defp socket_init(socket) do
    with avatars = Game.list_avatars(),
         ultimates = Game.list_ultimate_skills(),
         normals = Game.list_normal_skills() |> Enum.group_by(fn skill -> skill.code end),
         sidebar_code = "library" do
      assign(socket, avatars: avatars, skills: normals, sidebar_code: sidebar_code, ultimates: ultimates)
    end
  end
end
