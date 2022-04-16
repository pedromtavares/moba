defmodule MobaWeb.ArenaLiveView do
  use MobaWeb, :live_view

  alias MobaWeb.{ArenaView, Presence, Tutorial}

  def mount(_, _session, %{assigns: %{current_user: user}} = socket) do
    if connected?(socket) do
      Tutorial.subscribe(user.id)
    end

    normal_count = Accounts.normal_matchmaking_count(user)
    elite_count = Accounts.elite_matchmaking_count(user)
    matchmaking = Game.list_matchmaking(user)
    battles = matchmaking |> Enum.map(& &1.id) |> Engine.list_duel_battles()
    pending_match = Enum.find(matchmaking, &(&1.phase != "finished"))
    closest_bot_time = normal_count == 0 && elite_count == 0 && Accounts.closest_bot_time(user)

    Process.send_after(self(), :refresh_duel_opponents, 500)

    {:ok,
     assign(socket,
       battles: battles,
       current_time: Timex.now(),
       duel_opponents: [],
       elite_count: elite_count,
       normal_count: normal_count,
       matchmaking: matchmaking,
       pending_match: pending_match,
       closest_bot_time: closest_bot_time,
       sidebar_code: "arena",
       tutorial_step: user.tutorial_step
     )}
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
      {:noreply, push_redirect(socket, to: Routes.live_path(socket, MobaWeb.DuelLiveView, duel.id))}
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
    {:noreply, socket |> Tutorial.next_step(31)}
  end

  def handle_event("finish-tutorial", _, socket) do
    {:noreply, Tutorial.finish_arena(socket)}
  end

  def handle_info({"tutorial-step", %{step: step}}, socket) do
    {:noreply, assign(socket, tutorial_step: step)}
  end

  def handle_info(:refresh_duel_opponents, %{assigns: %{current_user: user}} = socket) do
    duel_opponents = if user.status == "available", do: opponents_from_presence(user), else: []

    Process.send_after(self(), :refresh_duel_opponents, 5000)

    {:noreply, assign(socket, duel_opponents: duel_opponents, current_time: Timex.now())}
  end

  def render(assigns) do
    ArenaView.render("index.html", assigns)
  end

  defp can_duel?(user) do
    user.status == "available" && ArenaView.can_be_challenged?(user, Timex.now())
  end

  defp opponents_from_presence(user) do
    online_ids =
      Presence.list("online")
      |> Enum.map(fn {_user_id, data} -> List.first(data[:metas]) end)
      |> Enum.map(& &1.user_id)

    Accounts.duel_opponents(user, online_ids)
  end
end
