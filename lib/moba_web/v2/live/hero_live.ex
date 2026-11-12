defmodule MobaWeb.V2.HeroLive do
  use MobaWeb, :v2_live_view

  import MobaWeb.CoreComponents, only: [icon: 1]

  import MobaWeb.V2.Components.ProgressionComponents
  import MobaWeb.V2.Components.TrainingComponents, only: [perfect_indicator: 1]

  import MobaWeb.V2.Components.HeroBarComponents

  embed_templates "hero_live/*"

  def mount(_params, _session, socket) do
    socket =
      attach_hook(socket_init(socket), :authorize_hero_changes, :handle_event, fn event, _, socket ->
        if event in ~w(toggle-customize set-skin level skill start-edit finalize-edit reorder-items open-shop-item buy sell finish-transmute forge) do
          hero = Game.get_hero!(socket.assigns.hero.id)

          if hero.player_id == socket.assigns.current_player.id do
            {:cont, assign(socket, hero: hero)}
          else
            {:halt, socket}
          end
        else
          {:cont, socket}
        end
      end)

    {:ok, socket}
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
     |> assign(hero: hero, ranking: ranking, show_hud: false, editing: false, show_build: false, show_shop: false)
     |> assign(:ranking_tab, if(hero.league_tier in 2..5, do: "league", else: "global"))
     |> league_assigns()
     |> owner_assigns()
     |> quest_assigns()}
  end

  def handle_event("ranking-tab", %{"type" => "league"}, %{assigns: %{hero: %{league_tier: tier}}} = socket)
      when tier < 2 or tier >= 6 do
    {:noreply, socket}
  end

  def handle_event("ranking-tab", %{"type" => tab}, socket) when tab in ["league", "global"] do
    {:noreply, socket |> assign(:ranking_tab, tab) |> leaderboard_assigns()}
  end

  def handle_event("ranking-tab", _, socket), do: {:noreply, socket}

  def handle_event("toggle-customize", _, %{assigns: %{hero: hero, current_player: player}} = socket)
      when hero.player_id == player.id do
    {:noreply, assign(socket, show_hud: !socket.assigns.show_hud, editing: false, show_build: false, show_shop: false)}
  end

  def handle_event("toggle-customize", _, socket), do: {:noreply, socket}

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

  def handle_event(
        "reorder-items",
        %{"codes" => codes, "hero_id" => hero_id},
        %{assigns: %{hero: hero, current_player: player, show_hud: true}} = socket
      ) do
    if hero.player_id == player.id && hero_id == to_string(hero.id) do
      {:noreply, update_hero_assigns(socket, Game.reorder_inventory!(player, hero, codes))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("reorder-items", _, socket), do: {:noreply, socket}

  def handle_event("cancel-edit", _, socket) do
    {:noreply, assign(socket, editing: false)}
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

  def handle_event("open-shop-item", %{"code" => code}, socket) do
    {:noreply, open_shop_item(socket, socket.assigns.hero, code)}
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

  def handle_event("forge", %{"legendary_code" => legendary, "epic_code" => epic}, socket)
      when is_binary(legendary) and is_binary(epic) do
    %{hero: hero, current_player: player} = socket.assigns
    {:noreply, update_hero_assigns(socket, Game.Items.forge_item!(player, hero, legendary, epic))}
  end

  def handle_event("forge", _, socket), do: {:noreply, socket}

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

  def handle_info({"hero", %{id: id}}, %{assigns: %{hero: %{id: id}}} = socket) do
    {:noreply, update_hero_assigns(socket, Game.get_hero!(id))}
  end

  def handle_info({"hero", _}, socket), do: {:noreply, socket}

  def handle_info({"ranking", _}, %{assigns: %{hero: %{id: id}}} = socket) do
    {:noreply,
     socket
     |> assign(ranking: Moba.pve_ranking())
     |> update_hero_assigns(Game.get_hero!(id))}
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
    |> league_assigns()
  end

  defp league_assigns(%{assigns: %{hero: hero}} = socket) do
    socket = if hero.league_tier >= 6, do: assign(socket, :ranking_tab, "global"), else: socket
    team_ranking = if hero.training_team_id, do: Game.TeamRuns.ranking(hero.training_team_id), else: []

    perfect_run =
      if hero.training_team_id do
        entry = Enum.find(team_ranking, &(&1.team.id == hero.training_team_id))
        entry && Game.Training.PerfectRun.completed_team?(entry.team)
      else
        Game.Training.PerfectRun.solo?(hero)
      end

    socket
    |> assign(
      league_ranking: Game.league_ranking(hero),
      league_milestone: if(hero.finished_at && perfect_run, do: nil, else: league_milestone(hero)),
      team_ranking: team_ranking,
      perfect_run: !!perfect_run
    )
    |> leaderboard_assigns()
  end

  defp leaderboard_assigns(%{assigns: %{ranking_tab: "league", league_ranking: ranking}} = socket) do
    assign(socket, leaderboard_entries: ranking.entries, leaderboard_position: ranking.position)
  end

  defp leaderboard_assigns(socket) do
    entries = Enum.map(socket.assigns.ranking, &%{hero: &1, position: &1.pve_ranking})
    assign(socket, leaderboard_entries: entries, leaderboard_position: socket.assigns.hero.pve_ranking)
  end

  defp league_milestone(%{league_tier: tier, player: player} = hero) when tier < 6 do
    next_tier = tier + 1
    name = Moba.leagues()[next_tier]

    description =
      cond do
        next_tier > Moba.max_available_league(player.pve_tier) ->
          Game.get_quest(player.pve_tier + 1).description <> " to unlock #{name}."

        hero.finished_at || next_tier > Moba.max_available_league(hero.pve_tier) ->
          "Reach #{name} on your next training run."

        tier == Moba.master_league_tier() ->
          "Defeat Roshan to reach Grandmaster League."

        true ->
          "Win the #{Moba.leagues()[tier]} challenge to advance."
      end

    %{
      tier: next_tier,
      title: if(next_tier > Moba.max_available_league(player.pve_tier), do: "Unlock #{name}", else: "Reach #{name}"),
      description: description
    }
  end

  defp league_milestone(_hero) do
    %{
      tier: 6,
      title: "Aim for a perfect 60K",
      description: "Finish a Grandmaster run with 30K XP farm and 30K gold farm."
    }
  end

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
