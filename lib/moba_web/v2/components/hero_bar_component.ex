defmodule MobaWeb.V2.HeroBarComponent do
  use MobaWeb, :v2_live_component

  alias MobaWeb.V2.TutorialComponent

  embed_templates "hero_bar_component/*"

  def update(assigns, socket) do
    hero = Map.get(assigns, :current_hero, socket.assigns[:current_hero])
    tutorial_step = Map.get(assigns, :tutorial_step, hero.player.tutorial_step)

    socket =
      if current_hero?(socket, hero) do
        socket
        |> assign(id: Map.get(assigns, :id, socket.assigns[:id]), current_hero: hero, tutorial_step: tutorial_step)
        |> maybe_close_shop(assigns)
      else
        socket
        |> assign(
          id: Map.get(assigns, :id, socket.assigns[:id]),
          current_hero: hero,
          tutorial_step: tutorial_step,
          editing: false,
          show_build: false,
          show_shop: Enum.member?([3, 7, 8, 9], tutorial_step)
        )
        |> maybe_close_shop(assigns)
      end

    {:ok, socket}
  end

  def handle_event("level", _, %{assigns: %{current_hero: current}} = socket) do
    hero =
      if Application.get_env(:moba, :env) == :dev do
        Game.level_cheat(current)
      else
        current
      end

    Game.broadcast_to_hero(current.id)

    {:noreply,
     socket
     |> assign(current_hero: hero)
     |> notify_parent(hero)}
  end

  def handle_event("skill", %{"code" => code}, %{assigns: %{current_hero: current}} = socket) do
    hero = Game.level_up_skill!(current, code)
    Game.broadcast_to_hero(hero.id)

    {:noreply,
     socket
     |> assign(current_hero: hero)
     |> notify_parent(hero)}
  end

  def handle_event("start-edit", _, socket) do
    {:noreply, assign(socket, editing: true)}
  end

  def handle_event("finalize-edit", params, %{assigns: %{current_hero: current}} = socket) do
    hero =
      Game.update_hero!(current, %{
        skill_order: params_to_order(params["skill_order"]),
        item_order: params_to_order(params["item_order"])
      })

    {:noreply,
     socket
     |> assign(editing: false, current_hero: hero)
     |> notify_parent(hero)}
  end

  def handle_event("show-build", _, socket) do
    {:noreply, assign(socket, show_build: true)}
  end

  def handle_event("show-navigation", _, socket) do
    {:noreply, assign(socket, show_build: false)}
  end

  def handle_event("close-shop", _, socket) do
    {:noreply, socket |> assign(show_shop: false) |> TutorialComponent.next_step(10)}
  end

  def handle_event("toggle-shop", _, socket) do
    {:noreply, assign(socket, show_shop: !socket.assigns.show_shop)}
  end

  def render(assigns) do
    hero_bar(assigns)
  end

  attr :current_hero, :map, required: true

  defp hero_bar_stats(assigns) do
    ~H"""
    <div class="btn-group stats-group f-rpg">
      <button
        class="btn btn-icon btn-outline-dark text-danger tooltip-mobile no-action"
        type="button"
        data-toggle="tooltip"
        title={total_hp_description(@current_hero)}
      >
        <i class="fa fa-heart mr-1"></i> {@current_hero.total_hp + @current_hero.item_hp}
      </button>
      <button
        class="btn btn-icon btn-outline-dark text-info tooltip-mobile no-action"
        type="button"
        data-toggle="tooltip"
        title={total_mp_description(@current_hero)}
      >
        <i class="fa fa-bolt"></i> {@current_hero.total_mp + @current_hero.item_mp}
      </button>
      <button
        class="btn btn-icon btn-outline-dark text-success tooltip-mobile no-action"
        type="button"
        data-toggle="tooltip"
        title={total_atk_description(@current_hero)}
      >
        <i class="fa fa-dagger"></i> {@current_hero.atk + @current_hero.item_atk}
      </button>
      <button
        class="btn btn-icon btn-outline-dark text-pink tooltip-mobile no-action"
        type="button"
        data-toggle="tooltip"
        title={total_power_description(@current_hero)}
      >
        <i class="fa fa-galaxy"></i> {@current_hero.power + @current_hero.item_power}
      </button>
      <button
        class="btn btn-icon btn-outline-dark text-warning tooltip-mobile no-action"
        type="button"
        data-toggle="tooltip"
        title={total_armor_description(@current_hero)}
      >
        <i class="fa fa-shield-halved"></i> {@current_hero.armor + @current_hero.item_armor}
      </button>
      <button
        class="btn btn-icon btn-outline-dark text-orange tooltip-mobile no-action"
        type="button"
        data-toggle="tooltip"
        title={total_speed_description(@current_hero)}
      >
        <i class="fa fa-running"></i> {@current_hero.speed + @current_hero.item_speed}
      </button>
    </div>
    """
  end

  defp params_to_order(nil), do: []

  defp params_to_order(params) do
    Enum.sort(params, fn {_, v1}, {_, v2} ->
      String.to_integer(v1) <= String.to_integer(v2)
    end)
    |> Enum.map(fn {code, _} -> code end)
  end

  defp edit_orders_label(%{finished_at: finished_at}) when is_nil(finished_at) do
    "Click to edit the skill and item orders that will be preselected so you don't have to manually select them in every battle."
  end

  defp edit_orders_label(_) do
    "Click to edit the skill and item orders that will be used when defending against other players in the Arena."
  end

  defp sorted_items(%{items: items}), do: Game.sort_items(items)
  defp sorted_skills(%{skills: skills}), do: Enum.sort_by(skills, &{&1.ultimate, &1.passive, &1.name})
  defp can_level_skill?(hero, skill), do: Game.can_level_skill?(hero, skill)
  defp max_skill_level(skill), do: Game.max_skill_level(skill)
  defp xp_percentage(hero), do: hero.experience * 100 / xp_to_next_level(hero)
  defp xp_to_next_level(hero), do: Game.xp_to_next_hero_level(hero.level + 1)

  defp next_skill_description(skill) do
    next = Game.get_current_skill!(skill.code, skill.level + 1)

    "#{GH.skill_description(skill)}<hr/>#{GH.skill_description(%{next | name: "Next Level (#{next.level})", level: nil, description: ""})}"
  end

  defp total_hp_description(hero) do
    title = "Health: #{hero.total_hp + hero.item_hp}"
    sub = "Main survival stat. When it reaches 0 in a battle, you die and receive no rewards."

    main =
      "Current base Health: #{hero.total_hp} <br/>Health given by items: #{hero.item_hp}<br/><br/>Health gain on level up: #{hero.avatar.hp_per_level}"

    attribute_description(title, sub, main)
  end

  defp total_mp_description(hero) do
    title = "Energy: #{hero.total_mp + hero.item_mp}"

    sub =
      "Main spending stat, used to power abilities and active items. When it reaches 0 in a battle, you will hit with a Basic Attack, which deals 100% Attack as Normal Damage."

    main =
      "Current base Energy: #{hero.total_mp} <br/>Energy given by items: #{hero.item_mp}<br/><br/>Energy gain on level up: #{hero.avatar.mp_per_level}"

    attribute_description(title, sub, main)
  end

  defp total_atk_description(hero) do
    title = "Attack: #{hero.atk + hero.item_atk}"
    sub = "Base stat used to calculate damage in most skills and items."

    main =
      "Current Attack: #{hero.atk} <br/>Attack given by items: #{hero.item_atk}<br/><br/>Attack gain on level up: #{hero.avatar.atk_per_level}"

    attribute_description(title, sub, main)
  end

  defp total_power_description(hero) do
    title = "Power: #{hero.power + hero.item_power}"

    sub =
      "Amplifies your total damage output and regeneration in a turn by 1% for every point in Power. E.g. 10 Power will give you 10% amplification."

    main = "Current Power: #{hero.power} <br/>Power given by items: #{hero.item_power}"

    attribute_description(title, sub, main)
  end

  defp total_armor_description(hero) do
    title = "Armor: #{hero.armor + hero.item_armor}"

    sub =
      "Reduces incoming damage by 1% for every point of Armor, up to 90%. Can go negative, increasing damage taken."

    main = "Current Armor: #{hero.armor} <br/>Armor given by items: #{hero.item_armor}"

    attribute_description(title, sub, main)
  end

  defp total_speed_description(hero) do
    title = "Speed: #{hero.speed + hero.item_speed}"

    sub =
      "Determines chance to attack first in battle. Above 100, it also grants a chance to evade physical damage from non-ultimate skills."

    main = "Current Speed: #{hero.speed} <br/>Speed given by items: #{hero.item_speed}"

    attribute_description(title, sub, main)
  end

  defp attribute_description(title, sub, main) do
    "<h4>#{title}</h4><em>#{sub}</em><br/><br/>#{main}"
  end

  defp current_hero?(socket, hero) do
    socket.assigns[:current_hero] && socket.assigns.current_hero.id == hero.id
  end

  defp maybe_close_shop(socket, %{shop_action: :close}), do: assign(socket, show_shop: false)
  defp maybe_close_shop(socket, _), do: socket

  defp notify_parent(socket, hero) do
    send(self(), {:hero_bar_updated, hero})
    socket
  end
end
