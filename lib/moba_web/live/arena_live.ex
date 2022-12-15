defmodule MobaWeb.ArenaLive do
  use MobaWeb, :live_view

  alias MobaWeb.{ArenaView, Presence, TutorialComponent}

  def mount(_, _session, %{assigns: %{current_player: player}} = socket) do
    with socket = socket_init(socket) do
      if connected?(socket) do
        TutorialComponent.subscribe(player.id)
        MobaWeb.subscribe("online")
        MobaWeb.subscribe("player-ranking")
      end

      {:ok, socket}
    end
  end

  def handle_event("clear-auto-matches", _, %{assigns: %{current_player: player}} = socket) do
    player = Game.maybe_clear_auto_matches(player)

    {:noreply, assign(socket, current_player: player)}
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

  def handle_event("matchmaking", _, %{assigns: %{current_player: player}} = socket) do
    match = Game.manual_matchmaking!(player)

    if match do
      {:noreply, push_redirect(socket, to: Routes.live_path(socket, MobaWeb.MatchLive, match.id))}
    else
      {:noreply, assign(socket, current_player: Game.get_player!(player.id))}
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

  def handle_event("finish-tutorial", _, socket) do
    socket = TutorialComponent.next_step(socket, 31)

    handle_event("matchmaking", nil, socket)
  end

  def handle_info({:tutorial, %{step: step}}, socket) do
    {:noreply, assign(socket, tutorial_step: step)}
  end

  def handle_info(
        %{event: "presence_diff"},
        %{assigns: %{current_player: player, last_presence_update: last_update}} = socket
      ) do
    ago = Timex.shift(Timex.now(), seconds: -10)
    diff = Timex.diff(ago, last_update)

    if diff > 0 do
      {:noreply, assign(socket, duel_opponents: opponents_from_presence(player), last_presence_update: Timex.now())}
    else
      {:noreply, socket}
    end
  end

  def handle_info({"ranking", _}, %{assigns: %{current_player: %{id: id}}} = socket) do
    with player = Game.get_player!(id),
         ranking = tiered_ranking(player) do
      {:noreply, assign(socket, ranking: ranking, current_player: player)}
    end
  end

  def render(assigns) do
    ArenaView.render("index.html", assigns)
  end

  defp can_duel?(player) do
    player.status == "available" && ArenaView.can_be_challenged?(player, Timex.now())
  end

  defp check_tutorial(socket) do
    TutorialComponent.next_step(socket, 30)
  end

  defp maybe_redirect(%{assigns: %{current_player: %{user_id: user_id}}} = socket) when is_nil(user_id) do
    redirect(socket, to: "/registration/new")
  end

  defp maybe_redirect(socket), do: socket

  defp opponents_from_presence(%{status: "available"} = player) do
    online_ids =
      Presence.list("online")
      |> Enum.map(fn {_user_id, data} -> List.first(data[:metas]) end)
      |> Enum.map(& &1.player_id)

    Game.duel_opponents(player, online_ids)
    |> Enum.sort_by(& &1.user.last_online_at, {:asc, Date})
  end

  defp opponents_from_presence(_), do: []

  defp socket_init(%{assigns: %{current_player: player}} = socket) do
    with current_time = Timex.now(),
         sidebar_code = "arena",
         all_matches = Game.list_matches(player),
         matches = all_matches |> Enum.filter(&(&1.phase == "scored")),
         pending_match = Enum.find(all_matches, &(&1.phase != "scored")),
         duels = Game.list_duels(player),
         duel_opponents = opponents_from_presence(player),
         last_presence_update = Timex.now(),
         pending_duel = Enum.find(duels, &(&1.phase != "finished")),
         ranking = tiered_ranking(player) do
      assign(socket,
        closest_bot_time: current_time,
        current_time: current_time,
        duels: duels,
        duel_opponents: duel_opponents,
        matches: matches,
        pending_duel: pending_duel,
        pending_match: pending_match,
        last_presence_update: last_presence_update,
        ranking: ranking,
        sidebar_code: sidebar_code,
        tutorial_step: player.tutorial_step
      )
      |> maybe_redirect()
      |> check_tutorial()
    end
  end

  defp tiered_ranking(%{pvp_tier: tier}) do
    Moba.daily_ranking()
    |> Enum.filter(fn player -> player.pvp_tier == tier end)
  end
end
