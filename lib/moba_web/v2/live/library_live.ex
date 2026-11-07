defmodule MobaWeb.V2.LibraryLive do
  use MobaWeb, :v2_live_view

  import MobaWeb.CoreComponents, only: [icon: 1]
  import MobaWeb.V2.Components.ManualComponents

  def mount(_, _session, socket) do
    socket = assign_new(socket, :current_scope, fn -> Game.TeamRuns.scope(socket.assigns.current_player) end)
    {:ok, socket_init(socket)}
  end

  defp socket_init(socket) do
    ultimates = Game.list_ultimate_skills() |> rank_groups() |> Map.new(fn {first, levels} -> {first.code, levels} end)

    avatars =
      Game.list_avatars()
      |> Enum.sort_by(&{if(&1.code == "juggernaut", do: 0, else: 1), &1.name})
      |> Enum.map(&Map.put(&1, :ultimate_ranks, Map.get(ultimates, &1.ultimate_code, [])))

    skills = Game.list_normal_skills() |> rank_groups()

    assign(socket,
      avatars: avatars,
      skills: skills,
      items: Moba.cached_items(),
      sidebar_code: "library"
    )
  end

  defp rank_groups(skills) do
    skills
    |> Enum.group_by(& &1.code)
    |> Enum.map(fn {_code, levels} ->
      levels = levels |> Enum.sort_by(&{&1.level, -&1.id}) |> Enum.uniq_by(& &1.level)
      {hd(levels), levels}
    end)
    |> Enum.sort_by(fn {first, _} -> first.name end)
  end
end
