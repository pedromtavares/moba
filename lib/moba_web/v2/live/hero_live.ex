defmodule MobaWeb.V2.HeroLive do
  use MobaWeb, :v2_live_view

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

  def handle_info({"hero", %{id: id}}, socket) do
    {:noreply, assign(socket, hero: Game.get_hero!(id))}
  end

  def handle_info({"ranking", _}, %{assigns: %{hero: %{id: id}}} = socket) do
    {:noreply, assign(socket, ranking: Moba.pve_ranking(), hero: Game.get_hero!(id))}
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
  end

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

  defp hero_stats_buttons(assigns) do
    ~H"""
    <div class="btn-group hero-stats">
      <button class="btn btn-icon waves-effect btn-outline-dark text-danger" data-toggle="tooltip" title="Health">
        <i class="fa fa-heart mr-1"></i> {@hero.total_hp + @hero.item_hp}
      </button>
      <button
        class="btn btn-icon waves-effect waves-light btn-outline-dark text-info"
        data-toggle="tooltip"
        title="Energy"
      >
        <i class="fa fa-bolt"></i> {@hero.total_mp + @hero.item_mp}
      </button>
      <button
        class="btn btn-icon waves-effect waves-light btn-outline-dark text-success"
        data-toggle="tooltip"
        title="Attack"
      >
        <i class="fa fa-dagger"></i> {@hero.atk + @hero.item_atk}
      </button>
      <button class="btn btn-icon waves-effect waves-light btn-outline-dark text-pink" data-toggle="tooltip" title="Power">
        <i class="fa fa-galaxy"></i> {@hero.power + @hero.item_power}
      </button>
      <button
        class="btn btn-icon waves-effect waves-light btn-outline-dark text-warning"
        data-toggle="tooltip"
        title="Armor"
      >
        <i class="fa fa-shield-halved"></i> {@hero.armor + @hero.item_armor}
      </button>
      <button
        class="btn btn-icon waves-effect waves-light btn-outline-dark text-orange"
        data-toggle="tooltip"
        title="Speed"
      >
        <i class="fa fa-running"></i> {@hero.speed + @hero.item_speed}
      </button>
    </div>
    """
  end

  defp training_difficulty_for(tier) do
    Map.get(Game.get_quest(tier), :difficulty) || Game.get_quest(7).difficulty
  end

  defp training_bonus_for(tier), do: Map.get(Game.get_quest(tier), :training_bonus)
  defp max_league_allowed_for(tier), do: Map.get(Game.get_quest(tier), :max_league) || Game.get_quest(7).max_league
  defp quest_shard_prize(tier), do: Game.get_quest(tier).prize
end
