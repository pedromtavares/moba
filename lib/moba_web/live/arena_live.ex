defmodule MobaWeb.ArenaLive do
  use MobaWeb, :live_view

  alias MobaWeb.{ArenaView, Presence, TutorialComponent}

  def mount(_, _session, %{assigns: %{current_player: player}} = socket) do
    with socket = socket_init(socket) do
      if connected?(socket) do
        TutorialComponent.subscribe(player.id)
        MobaWeb.subscribe("online")
      end

      {:ok, socket}
    end
  end

  def handle_event("challenge", %{"id" => opponent_id}, %{assigns: %{current_player: player}} = socket) do
    opponent = Game.get_player!(opponent_id)

    if can_duel?(player) && can_duel?(opponent) do
      Game.duel_challenge(player, opponent)
      {:noreply, socket}
    else
      {:noreply, assign(socket, duel_opponents: opponents_from_presence(player))}
    end
  end

  def handle_event("matchmaking", %{"type" => type}, %{assigns: %{current_player: player}} = socket) do
    duel = if type == "elite", do: Game.elite_matchmaking!(player), else: Game.normal_matchmaking!(player)

    if duel do
      {:noreply, push_redirect(socket, to: Routes.live_path(socket, MobaWeb.DuelLive, duel.id))}
    else
      {:noreply,
       assign(socket,
         normal_count: Game.normal_matchmaking_count(player),
         elite_count: Game.elite_matchmaking_count(player)
       )}
    end
  end

  def handle_event("set-status", params, %{assigns: %{current_player: player}} = socket) do
    {player, duel_opponents} =
      if is_nil(Map.get(params, "value")) do
        {Game.set_player_unavailable!(player), []}
      else
        {Game.set_player_available!(player), opponents_from_presence(player)}
      end

    {:noreply, assign(socket, current_player: player, duel_opponents: duel_opponents)}
  end

  def handle_event("tutorial1", _, socket) do
    {:noreply, socket |> TutorialComponent.next_step(31)}
  end

  def handle_event("finish-tutorial", _, socket) do
    {:noreply, TutorialComponent.finish_arena(socket)}
  end

  def handle_info({:tutorial, %{step: step}}, socket) do
    {:noreply, assign(socket, tutorial_step: step)}
  end

  def handle_info(%{event: "presence_diff"}, %{assigns: %{current_player: player}} = socket) do
    duel_opponents = if player.status == "available", do: opponents_from_presence(player), else: []

    {:noreply, assign(socket, duel_opponents: duel_opponents)}
  end

  def render(assigns) do
    ArenaView.render("index.html", assigns)
  end

  defp can_duel?(player) do
    player.status == "available" && ArenaView.can_be_challenged?(player, Timex.now())
  end

  defp maybe_redirect(%{assigns: %{current_player: %{user_id: user_id}}} = socket) when is_nil(user_id) do
    redirect(socket, to: "/registration/new")
  end

  defp maybe_redirect(%{assigns: %{current_player: %{hero_collection: collection}}} = socket)
       when length(collection) < 2 do
    redirect(socket, to: "/base")
  end

  defp maybe_redirect(socket), do: socket

  defp opponents_from_presence(player) do
    online_ids =
      Presence.list("online")
      |> Enum.map(fn {_user_id, data} -> List.first(data[:metas]) end)
      |> Enum.map(& &1.player_id)

    Game.duel_opponents(player, online_ids)
    |> Enum.sort_by(& &1.user.last_online_at, {:asc, Date})
  end

  defp socket_init(%{assigns: %{current_player: player}} = socket) do
    with current_time = Timex.now(),
         sidebar_code = "arena",
         normal_count = Game.normal_matchmaking_count(player),
         elite_count = Game.elite_matchmaking_count(player),
         matchmaking = Game.list_matchmaking(player),
         battles = matchmaking |> Enum.map(& &1.id) |> Engine.list_duel_battles(),
         pending_match = Enum.find(matchmaking, &(&1.phase != "finished")),
         closest_bot_time = normal_count == 0 && elite_count == 0 && Game.closest_bot_time(player),
         duels = Game.list_pvp_duels(player),
         duel_battles = duels |> Enum.map(& &1.id) |> Engine.list_duel_battles(),
         pending_duel = Enum.find(duels, &(&1.phase != "finished")) do
      assign(socket,
        battles: battles,
        closest_bot_time: closest_bot_time,
        current_time: current_time,
        duels: duels,
        duel_battles: duel_battles,
        duel_opponents: [],
        elite_count: elite_count,
        matchmaking: matchmaking,
        normal_count: normal_count,
        pending_duel: pending_duel,
        pending_match: pending_match,
        sidebar_code: sidebar_code,
        tutorial_step: player.tutorial_step
      )
      |> maybe_redirect()
    end
  end
end
