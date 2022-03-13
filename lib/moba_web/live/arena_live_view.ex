defmodule MobaWeb.ArenaLiveView do
  use MobaWeb, :live_view
  import Appsignal.Phoenix.LiveView, only: [instrument: 4]

  def mount(_, session, socket) do
    instrument(__MODULE__, "mount", socket, fn ->
      socket = assign_new(socket, :current_user, fn -> Accounts.get_user!(session["user_id"]) end)
      user = socket.assigns.current_user
      eligible_heroes = Game.eligible_heroes_for_pvp(user.id, Timex.now())

      if length(eligible_heroes) >= 2 do
        duel_users = if user.status == "available", do: Accounts.list_duel_users(user), else: []
        normal_count = Accounts.normal_matchmaking_count(user)
        elite_count = Accounts.elite_matchmaking_count(user)
        matchmaking = Game.list_matchmaking(user)
        pending_match = Enum.find(matchmaking, &(&1.phase != "finished"))
        closest_bot_time = normal_count == 0 && elite_count == 0 && Accounts.closest_bot_time(user)

        {:ok,
         assign(socket,
           duel_users: duel_users,
           elite_count: elite_count,
           normal_count: normal_count,
           matchmaking: matchmaking,
           pending_match: pending_match,
           closest_bot_time: closest_bot_time
         )}
      else
        {:ok, socket |> push_redirect(to: "/base")}
      end
    end)
  end

  def handle_event("challenge", %{"id" => opponent_id}, socket) do
    opponent = Accounts.get_user!(opponent_id)
    Game.duel_challenge(socket.assigns.current_user, opponent)

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

  def render(assigns) do
    MobaWeb.ArenaView.render("index.html", assigns)
  end
end
