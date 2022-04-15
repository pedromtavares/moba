defmodule MobaWeb.CurrentUserLiveView do
  use MobaWeb, :live_view
  alias MobaWeb.Presence

  @default_title "Browser MOBA - Free Strategy Game"

  def mount(_, %{"user_id" => user_id}, socket) do
    %{assigns: %{current_user: current_user}} =
      socket = assign_new(socket, :current_user, fn -> Accounts.get_user!(user_id) end)

    if connected?(socket) do
      MobaWeb.subscribe("user-#{user_id}")

      Presence.track(
        self(),
        "online",
        current_user.id,
        %{
          season_tier: current_user.season_tier,
          season_points: current_user.season_points,
          user_id: current_user.id
        }
      )
    end

    {:ok, assign(socket, challenge: nil)}
  end

  def handle_event("close", _, socket) do
    {:noreply, assign(socket, challenge: nil)}
  end

  def handle_event("accept", _, %{assigns: %{challenge: challenge, current_user: current_user}} = socket) do
    {user, opponent} =
      if challenge.challenger do
        {current_user, challenge.other}
      else
        {challenge.other, current_user}
      end

    Game.create_pvp_duel!(user, opponent)

    {:noreply, assign(socket, challenge: nil, page_title: @default_title)}
  end

  def handle_event("reject", _, %{assigns: %{challenge: challenge, current_user: current_user}} = socket) do
    MobaWeb.broadcast("user-#{challenge.other_id}", "reject", %{})
    user = Accounts.update_user!(current_user, %{last_challenge_at: nil})

    {:noreply, assign(socket, challenge: nil, user: user, page_title: @default_title)}
  end

  def handle_info({"reject", _}, %{assigns: %{current_user: current_user}} = socket) do
    user = Accounts.update_user!(current_user, %{last_challenge_at: nil})
    {:noreply, assign(socket, challenge: nil, user: user)}
  end

  def handle_info({"duel", %{id: id}}, socket) do
    {:noreply, socket |> push_redirect(to: Routes.live_path(socket, MobaWeb.DuelLiveView, id))}
  end

  def handle_info(
        {"challenge", %{user_id: user_id, opponent_id: opponent_id}},
        %{assigns: %{current_user: current_user}} = socket
      ) do
    challenge =
      if current_user.id == user_id do
        %{challenger: true, other: Accounts.get_user!(opponent_id), other_id: opponent_id}
      else
        %{challenger: false, other: Accounts.get_user!(user_id), other_id: user_id}
      end

    user = Accounts.update_user!(current_user, %{last_challenge_at: Timex.now()})
    title = unless challenge.challenger, do: "CHALLENGE!", else: nil

    {:noreply, assign(socket, challenge: challenge, current_user: user, page_title: title)}
  end

  def render(assigns) do
    MobaWeb.LayoutView.render("current_user.html", assigns)
  end
end
