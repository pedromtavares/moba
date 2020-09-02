defmodule MobaWeb.LibraryLiveView do
  use Phoenix.LiveView

  alias Moba.Game
  alias MobaWeb.LibraryView

  def mount(_, session, socket) do
    hero_id = Map.get(session, "hero_id")
    hero = hero_id && Game.get_hero!(hero_id)

    avatars = Game.list_avatars()
    ultimates = Game.list_ultimate_skills()

    normals =
      Game.list_normal_skills()
      |> Enum.group_by(fn skill -> skill.code end)

    {:ok, assign(socket, avatars: avatars, ultimates: ultimates, skills: normals, current_hero: hero)}
  end

  def render(assigns) do
    LibraryView.render("index.html", assigns)
  end
end
