defmodule MobaWeb.ArenaLive do
  use MobaWeb, :live_view

  alias MobaWeb.{ArenaView, Presence, TutorialComponent}

  def mount(_, _session, %{assigns: %{current_user: user}} = socket) do
    with socket = socket_init(socket) do
      if connected?(socket) do
        TutorialComponent.subscribe(user.id)
        MobaWeb.subscribe("online")
      end

      {:ok, socket}
    end
  end

  def handle_event("challenge", %{"id" => opponent_id}, %{assigns: %{current_user: user}} = socket) do
    opponent = Accounts.get_user!(opponent_id)

    if can_duel?(user) && can_duel?(opponent) do
      Game.duel_challenge(user, opponent)
      {:noreply, socket}
    else
      {:noreply, assign(socket, duel_opponents: opponents_from_presence(user))}
    end
  end

  def handle_event("matchmaking", %{"type" => type}, %{assigns: %{current_user: user}} = socket) do
    duel = if type == "elite", do: Moba.elite_matchmaking!(user), else: Moba.normal_matchmaking!(user)

    if duel do
      {:noreply, push_redirect(socket, to: Routes.live_path(socket, MobaWeb.DuelLive, duel.id))}
    else
      {:noreply,
       assign(socket,
         normal_count: Accounts.normal_matchmaking_count(user),
         elite_count: Accounts.elite_matchmaking_count(user)
       )}
    end
  end

  def handle_event("set-status", params, %{assigns: %{current_user: user}} = socket) do
    {user, duel_opponents} =
      if is_nil(Map.get(params, "value")) do
        {Accounts.set_unavailable!(user), []}
      else
        {Accounts.set_available!(user), opponents_from_presence(user)}
      end

    {:noreply, assign(socket, current_user: user, duel_opponents: duel_opponents)}
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

  def handle_info(%{event: "presence_diff"}, %{assigns: %{current_user: user}} = socket) do
    duel_opponents = if user.status == "available", do: opponents_from_presence(user), else: []

    {:noreply, assign(socket, duel_opponents: duel_opponents)}
  end

  def render(assigns) do
    ArenaView.render("index.html", assigns)
  end

  defp can_duel?(user) do
    user.status == "available" && ArenaView.can_be_challenged?(user, Timex.now())
  end

  defp maybe_redirect(%{assigns: %{current_user: %{is_guest: true}}} = socket) do
    redirect(socket, to: "/registration/edit")
  end

  defp maybe_redirect(%{assigns: %{current_user: %{hero_collection: collection}}} = socket)
       when length(collection) < 2 do
    redirect(socket, to: "/base")
  end

  defp maybe_redirect(socket), do: socket

  defp opponents_from_presence(user) do
    online_ids =
      Presence.list("online")
      |> Enum.map(fn {_user_id, data} -> List.first(data[:metas]) end)
      |> Enum.map(& &1.user_id)

    Accounts.duel_opponents(user, online_ids)
  end

  defp socket_init(%{assigns: %{current_user: user}} = socket) do
    with current_time = Timex.now(),
         sidebar_code = "arena",
         normal_count = Accounts.normal_matchmaking_count(user),
         elite_count = Accounts.elite_matchmaking_count(user),
         matchmaking = Game.list_matchmaking(user),
         battles = matchmaking |> Enum.map(& &1.id) |> Engine.list_duel_battles(),
         pending_match = Enum.find(matchmaking, &(&1.phase != "finished")),
         closest_bot_time = normal_count == 0 && elite_count == 0 && Accounts.closest_bot_time(user),
         duels = Game.list_pvp_duels(user),
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
        tutorial_step: user.tutorial_step
      )
      |> maybe_redirect()
    end
  end
end
