defmodule MobaWeb.V2.LibraryLive do
  use MobaWeb, :v2_live_view

  def mount(_, _session, socket) do
    {:ok, socket_init(socket)}
  end

  # Private functions

  defp socket_init(socket) do
    avatars = Game.list_avatars()
    ultimates = Game.list_ultimate_skills()

    skills =
      Game.list_normal_skills()
      |> Enum.group_by(& &1.code)
      |> Enum.map(fn {_code, levels} ->
        sorted = Enum.sort_by(levels, & &1.level)
        {List.first(sorted), sorted}
      end)

    assign(socket,
      avatars: avatars,
      skills: skills,
      ultimates: ultimates,
      sidebar_code: "library"
    )
  end

  defp ultimates_for(avatar, ultimates) do
    ultimates
    |> Enum.filter(fn ult -> ult.code == avatar.ultimate_code end)
    |> Enum.sort_by(fn ult -> ult.level end)
  end
end
