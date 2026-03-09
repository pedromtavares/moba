defmodule MobaWeb.V2.HeroLive do
  use MobaWeb, :v2_live_view

  import MobaWeb.V2.Components.HeroBarComponents

  def mount(_params, _session, socket) do
    {:ok, socket_init(socket)}
  end

  def handle_params(%{"id" => id}, _uri, socket) do
    hero = Game.get_hero!(id)
    ranking = Moba.pve_ranking()

    if connected?(socket) do
      Game.subscribe_to_hero(id)
      MobaWeb.subscribe("hero-ranking")
    end

    {:noreply,
     socket
     |> assign(hero: hero, ranking: ranking)
     |> owner_assigns()
     |> quest_assigns()}
  end

  def handle_event(
        "set-skin",
        %{"skin-code" => skin_code},
        %{assigns: %{skin_selection: selection, hero: hero}} = socket
      ) do
    skin = Enum.find(selection.skins, &(&1.code == skin_code))
    updated_hero = Game.set_skin!(hero, skin)
    skin_index = Enum.find_index(selection.skins, &(&1.code == skin_code))
    updated_selection = Map.put(selection, :index, skin_index)

    {:noreply, assign(socket, hero: updated_hero, skin_selection: updated_selection)}
  end

  def handle_event("level", _, %{assigns: %{hero: current}} = socket) do
    hero =
      if Application.get_env(:moba, :env) == :dev do
        Game.level_cheat(current)
      else
        current
      end

    Game.broadcast_to_hero(current.id)
    {:noreply, update_hero_assigns(socket, hero)}
  end

  def handle_event("skill", %{"code" => code}, %{assigns: %{hero: current}} = socket) do
    hero = Game.level_up_skill!(current, code)
    Game.broadcast_to_hero(hero.id)
    {:noreply, update_hero_assigns(socket, hero)}
  end

  def handle_event("start-edit", _, socket) do
    {:noreply, assign(socket, editing: true)}
  end

  def handle_event("finalize-edit", params, %{assigns: %{hero: current}} = socket) do
    hero =
      Game.update_hero!(current, %{
        skill_order: params_to_order(params["skill_order"]),
        item_order: params_to_order(params["item_order"])
      })

    {:noreply, socket |> assign(editing: false) |> update_hero_assigns(hero)}
  end

  def handle_event("show-build", _, socket) do
    {:noreply, assign(socket, show_build: true)}
  end

  def handle_event("show-navigation", _, socket) do
    {:noreply, assign(socket, show_build: false)}
  end

  def handle_event("close-shop", _, socket) do
    {:noreply, assign(socket, show_shop: false)}
  end

  def handle_event("toggle-shop", _, socket) do
    {:noreply, assign(socket, show_shop: !socket.assigns.show_shop)}
  end

  def handle_event("buy", %{"code" => code}, %{assigns: %{hero: hero}} = socket) do
    updated_hero = Game.buy_item!(hero, cached_item!(code))
    Game.broadcast_to_hero(updated_hero.id)
    {:noreply, update_hero_assigns(socket, updated_hero)}
  end

  def handle_event("sell", %{"code" => code}, %{assigns: %{hero: hero}} = socket) do
    updated_hero = Game.sell_item!(hero, hero_item_by_code!(hero, code))
    Game.broadcast_to_hero(updated_hero.id)
    {:noreply, update_hero_assigns(socket, updated_hero)}
  end

  def handle_event(
        "finish-transmute",
        %{"transmute_code" => transmute_code, "recipe_codes" => recipe_codes},
        %{assigns: %{hero: hero}} = socket
      ) do
    transmute = cached_item!(transmute_code)
    recipe = hero_items_by_codes(hero, recipe_codes)
    updated_hero = Game.transmute_item!(hero, recipe, transmute)
    Game.broadcast_to_hero(updated_hero.id)
    {:noreply, update_hero_assigns(socket, updated_hero)}
  end

  def handle_info({"hero", %{id: id}}, socket) do
    {:noreply, socket |> update_hero_assigns(Game.get_hero!(id)) |> maybe_reset_shop()}
  end

  def handle_info({"ranking", _}, %{assigns: %{hero: %{id: id}}} = socket) do
    {:noreply,
     socket
     |> assign(ranking: Moba.pve_ranking())
     |> update_hero_assigns(Game.get_hero!(id))
     |> maybe_reset_shop()}
  end

  defp owner_assigns(
         %{
           assigns: %{
             hero: %{player_id: player_id} = hero,
             current_player: %{id: current_player_id, user: user}
           }
         } = socket
       )
       when player_id == current_player_id and not is_nil(user) do
    skins = user |> Accounts.unlocked_codes_for() |> Game.list_skins_with_codes()
    avatar_code = hero.avatar.code
    avatar_skins = [Game.default_skin(avatar_code)] ++ Enum.filter(skins, &(&1.avatar_code == avatar_code))
    skin_index = Enum.find_index(avatar_skins, &(&1.id == hero.skin_id))
    skin_selection = %{index: skin_index, skins: avatar_skins}
    assign(socket, skin_selection: skin_selection)
  end

  defp owner_assigns(socket), do: socket

  defp quest_assigns(%{assigns: %{hero: %{id: hero_id} = hero, current_hero: %{id: current_hero_id}}} = socket)
       when hero_id == current_hero_id do
    assign(socket, completed_quest: Game.last_completed_quest(hero))
  end

  defp quest_assigns(socket), do: socket

  defp socket_init(%{assigns: %{current_player: player}} = socket) do
    socket
    |> assign_new(:current_hero, fn -> player.current_pve_hero end)
    |> assign(:completed_quest, nil)
    |> assign(:skin_selection, nil)
    |> assign(:sidebar_code, nil)
    |> assign(:editing, false)
    |> assign(:show_build, false)
    |> assign(:show_shop, false)
    |> assign(:tutorial_step, player.tutorial_step)
  end

  defp maybe_assign_current_hero(%{assigns: %{current_hero: %{id: current_hero_id}}} = socket, %{id: hero_id} = hero)
       when current_hero_id == hero_id do
    assign(socket, current_hero: hero)
  end

  defp maybe_assign_current_hero(socket, _hero), do: socket

  defp just_finished_training?(_, %{finished_at: nil}), do: nil

  defp just_finished_training?(player, %{finished_at: finished_at} = hero) do
    ago = Timex.now() |> Timex.shift(days: -1)
    diff = Timex.diff(finished_at, ago)

    if player.current_pve_hero_id && diff > 0 do
      current_hero = Game.get_hero!(player.current_pve_hero_id)
      current_hero.finished_at && hero.id == current_hero.id && hero
    end
  end

  defp in_ranking?(ranking, %{id: id}) do
    ranking
    |> Enum.map(& &1.id)
    |> Enum.member?(id)
  end

  defp tier_class(tier, hero_tier) do
    cond do
      tier == hero_tier -> "current-tier"
      tier > hero_tier -> "next-tier"
      true -> "previous-tier"
    end
  end

  defp has_previous_skin?(selection), do: selection.index > 0
  defp has_next_skin?(selection), do: length(selection.skins) > selection.index + 1

  defp next_skin_for(selection) do
    selection.skins
    |> Enum.at(selection.index + 1)
    |> Map.fetch!(:code)
  end

  defp previous_skin_for(selection) do
    selection.skins
    |> Enum.at(selection.index - 1)
    |> Map.fetch!(:code)
  end

  defp update_hero_assigns(socket, hero) do
    socket
    |> assign(hero: hero)
    |> maybe_assign_current_hero(hero)
    |> quest_assigns()
  end

  defp maybe_reset_shop(%{assigns: %{hero: %{id: shown_id}, current_hero: %{id: current_id}}} = socket)
       when shown_id != current_id do
    assign(socket, show_shop: false)
  end

  defp maybe_reset_shop(socket), do: socket

  defp params_to_order(nil), do: []

  defp params_to_order(params) do
    Enum.sort(params, fn {_, v1}, {_, v2} ->
      String.to_integer(v1) <= String.to_integer(v2)
    end)
    |> Enum.map(fn {code, _} -> code end)
  end

  defp cached_item!(code) do
    Enum.find(Moba.cached_items(), &(&1.code == code))
  end

  defp hero_item_by_code!(hero, code) do
    Enum.find(hero.items, &(&1.code == code))
  end

  defp hero_items_by_codes(hero, codes) do
    {items, _remaining} =
      Enum.map_reduce(codes, hero.items, fn code, remaining_items ->
        {item, updated_items} = pop_item_by_code(remaining_items, code)
        {item, updated_items}
      end)

    items
  end

  defp pop_item_by_code(items, code) do
    {matched, rest} = Enum.split_with(items, &(&1.code == code))
    {List.first(matched), Enum.drop(matched, 1) ++ rest}
  end

  defp hero_stats_buttons(assigns) do
    ~H"""
    <.hero_stat_group hero={@hero} />
    """
  end

  defp training_difficulty_for(tier) do
    Map.get(Game.get_quest(tier), :difficulty) || Game.get_quest(7).difficulty
  end

  defp training_bonus_for(tier), do: Map.get(Game.get_quest(tier), :training_bonus)
  defp max_league_allowed_for(tier), do: Map.get(Game.get_quest(tier), :max_league) || Game.get_quest(7).max_league
  defp quest_shard_prize(tier), do: Game.get_quest(tier).prize
end
