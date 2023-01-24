defmodule MobaWeb.ArenaLive.Edit do
  use MobaWeb, :live_view

  alias MobaWeb.ArenaView

  def mount(_, _session, socket) do
    with socket = socket_init(socket) do
      {:ok, socket}
    end
  end

  def handle_event("hero-list", params, socket) do
    with heroes_tab = Map.get(params, "type"),
         heroes = heroes_for(socket, heroes_tab) do
      {:noreply, assign(socket, heroes: heroes, heroes_tab: heroes_tab)}
    end
  end

  def handle_event("toggle-defensive", params, %{assigns: %{selected_team: team}} = socket) do
    with defensive = not is_nil(Map.get(params, "value")),
         team = Game.update_team!(team, %{defensive: defensive}) do
      {:noreply, assign(socket, selected_team: team) |> update_teams()}
    end
  end

  def handle_event("new-team", %{"name" => name}, socket) do
    team = Game.create_team!(%{name: name, player_id: socket.assigns.current_player.id})
    teams = socket.assigns.teams ++ [team]
    {:noreply, assign(socket, teams: teams, selected_team: team)}
  end

  def handle_event("select-team", %{"id" => id}, socket) do
    team = Enum.find(socket.assigns.teams, &(&1.id == String.to_integer(id)))
    {:noreply, assign(socket, selected_team: team)}
  end

  def handle_event("remove-team", _, socket) do
    Game.delete_team!(socket.assigns.selected_team)
    teams = socket.assigns.teams -- [socket.assigns.selected_team]
    {:noreply, assign(socket, selected_team: List.first(teams), teams: teams)}
  end

  def handle_event("edit-hero", %{"id" => id}, socket) do
    %{hero: current_hero, current_player: current_player} = socket.assigns
    hero = Game.get_hero!(id)

    if hero.player_id == current_player.id do
      if !current_hero || current_hero.id != hero.id do
        Process.send_after(self(), {"hero", %{id: hero.id}}, 10)
      end

      {:noreply, assign(socket, hero: nil)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("add-hero", %{"id" => id}, socket) do
    %{selected_team: selected_team} = socket.assigns
    hero = Game.get_hero!(id)

    if Game.available_hero?(hero) && length(selected_team.pick_ids) < 5 do
      team = Game.update_team!(selected_team, %{pick_ids: selected_team.pick_ids ++ [hero.id]})
      {:noreply, assign(socket, selected_team: team) |> update_teams()}
    else
      {:noreply, socket}
    end
  end

  def handle_event("remove-hero", %{"id" => id}, socket) do
    %{selected_team: selected_team} = socket.assigns

    team = Game.update_team!(selected_team, %{pick_ids: selected_team.pick_ids -- [String.to_integer(id)]})

    {:noreply, assign(socket, selected_team: team) |> update_teams()}
  end

  def handle_event("move-up", %{"id" => id}, socket) do
    hero_id = String.to_integer(id)
    {:noreply, move(hero_id, -1, socket)}
  end

  def handle_event("move-down", %{"id" => id}, socket) do
    hero_id = String.to_integer(id)
    {:noreply, move(hero_id, +1, socket)}
  end

  def handle_event("sort", _, socket) do
    %{sort: sort, trained_heroes: trained_heroes} = socket.assigns

    {sort, trained_heroes} =
      if sort == :recent do
        {:rank, Enum.sort_by(trained_heroes, & &1.pve_ranking)}
      else
        {:recent, Enum.sort_by(trained_heroes, & &1.finished_at, {:desc, Date})}
      end

    {:noreply, assign(socket, sort: sort, trained_heroes: trained_heroes)}
  end

  def handle_info({"hero", %{id: id}}, socket) do
    hero = Game.get_hero!(id)
    {:noreply, assign(socket, hero: hero)}
  end

  def render(assigns) do
    ArenaView.render("edit.html", assigns)
  end

  defp heroes_for(%{assigns: %{current_player: player}}, "trained") do
    Game.trained_pvp_heroes(player.id, [], 200) |> Enum.sort_by(& &1.pve_ranking)
  end

  defp heroes_for(_, _), do: Moba.pve_ranking_available()

  defp move(hero_id, slide, socket) do
    %{selected_team: selected_team} = socket.assigns
    index = Enum.find_index(selected_team.pick_ids, &(&1 == hero_id))
    pick_ids = Enum.slide(selected_team.pick_ids, index, index + slide)

    team = Game.update_team!(selected_team, %{pick_ids: pick_ids})
    assign(socket, selected_team: team) |> update_teams()
  end

  defp socket_init(%{assigns: %{current_player: player}} = socket) do
    with sidebar_code = "arena",
         match = Game.latest_manual_match(player),
         heroes_tab = "trained",
         heroes = heroes_for(socket, heroes_tab),
         teams = Game.list_teams(player) do
      assign(socket,
        sidebar_code: sidebar_code,
        hero: nil,
        heroes_tab: heroes_tab,
        match: match,
        heroes: heroes,
        teams: teams,
        sort: :rank,
        selected_team: List.first(teams)
      )
    end
  end

  defp update_teams(socket) do
    %{teams: teams, selected_team: %{id: selected_id} = selected} = socket.assigns

    teams =
      Enum.map(teams, fn
        %{id: ^selected_id} -> selected
        team -> team
      end)

    assign(socket, teams: teams)
  end
end
