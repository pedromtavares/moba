defmodule MobaWeb.ArenaLiveView do
  use MobaWeb, :live_view

  alias MobaWeb.Tutorial

  def mount(_, _session, %{assigns: %{current_user: user}} = socket) do
    if connected?(socket), do: Tutorial.subscribe(user.id)

    duel_users = if user.status == "available", do: Accounts.list_duel_users(user), else: []
    normal_count = Accounts.normal_matchmaking_count(user)
    elite_count = Accounts.elite_matchmaking_count(user)
    matchmaking = Game.list_matchmaking(user)
    battles = matchmaking |> Enum.map(& &1.id) |> Engine.list_duel_battles()
    pending_match = Enum.find(matchmaking, &(&1.phase != "finished"))
    closest_bot_time = normal_count == 0 && elite_count == 0 && Accounts.closest_bot_time(user)

    {:ok,
     assign(socket,
       battles: battles,
       duel_users: duel_users,
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
    Game.duel_challenge(user, opponent)

    {:noreply, socket}
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

  def handle_event("tutorial1", _, socket) do
    {:noreply, socket |> Tutorial.next_step(31)}
  end

  def handle_event("finish-tutorial", _, socket) do
    {:noreply, Tutorial.finish_arena(socket)}
  end

  def handle_info({"tutorial-step", %{step: step}}, socket) do
    {:noreply, assign(socket, tutorial_step: step)}
  end

  def render(assigns) do
    MobaWeb.ArenaView.render("index.html", assigns)
  end
end
