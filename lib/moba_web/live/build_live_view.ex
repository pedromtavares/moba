defmodule MobaWeb.BuildLiveView do
  use Phoenix.LiveView

  alias MobaWeb.BuildView
  alias Moba.{Accounts, Game}

  alias MobaWeb.Router.Helpers, as: Routes

  def mount(_params, %{"hero_id" => hero_id}, socket) do
    socket = assign_new(socket, :current_hero, fn -> Game.get_hero!(hero_id) end)
    hero = socket.assigns.current_hero

    unless Game.hero_has_other_build?(hero) do
      unlocked_codes = Accounts.unlocked_codes_for(hero.user)

      {:ok,
       assign(socket,
         max_skills: Game.list_creation_skills(5, unlocked_codes),
         selected_skills: [],
         ultimate: Enum.find(hero.active_build.skills, fn skill -> skill.ultimate end)
       )}
    else
      {:ok, socket |> push_redirect(to: "/")}
    end
  end

  def handle_event("pick-skill", %{"id" => id}, %{assigns: assigns} = socket) do
    skill = Game.get_skill!(id)

    selected_skills =
      if Enum.member?(assigns.selected_skills, skill) do
        remove_skill(assigns.selected_skills, skill)
      else
        add_skill(assigns.selected_skills, skill)
      end

    {:noreply, assign(socket, selected_skills: selected_skills)}
  end

  def handle_event(
        "create",
        _,
        %{assigns: %{selected_skills: selected_skills, current_hero: hero}} = socket
      ) do
    unlocked_codes = Accounts.unlocked_codes_for(hero.user)
    creation = Game.list_creation_skills(1, unlocked_codes)

    skills =
      selected_skills
      |> Enum.map(fn skill -> get_first_level_id_from(skill, creation) end)
      |> Game.list_chosen_skills()

    updated = Game.create_pvp_build!(hero, skills)

    {:noreply,
     socket |> assign(current_hero: updated) |> push_redirect(to: Routes.live_path(socket, MobaWeb.ArenaLiveView))}
  end

  def render(assigns) do
    BuildView.render("index.html", assigns)
  end

  defp add_skill(selected, skill) when length(selected) < 3 do
    selected ++ [skill]
  end

  defp add_skill(selected, _), do: selected

  defp remove_skill(selected, skill) do
    selected -- [skill]
  end

  defp get_first_level_id_from(skill, list) do
    Enum.find(list, fn item -> item.code == skill.code end)
    |> Map.get(:id)
  end
end
