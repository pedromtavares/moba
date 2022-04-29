defmodule MobaWeb.CurrentUserLiveView do
  use MobaWeb, :live_view
  alias MobaWeb.Presence

  @default_title "Browser MOBA - Free Strategy Game"

  def mount(_, %{"user_id" => user_id}, socket) do
    %{assigns: %{current_user: current_user}} =
      socket = assign_new(socket, :current_user, fn -> Accounts.get_user!(user_id) end)

    if connected?(socket) do
      MobaWeb.subscribe("user-#{user_id}")
      Presence.track_user(self(), current_user)
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
    user = update_user!(current_user, nil)

    {:noreply, assign(socket, challenge: nil, user: user, page_title: @default_title)}
  end

  def handle_info({"reject", _}, %{assigns: %{current_user: current_user}} = socket) do
    user = update_user!(current_user, nil)
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

    user = update_user!(current_user, Timex.now())
    title = unless challenge.challenger, do: "CHALLENGE!", else: nil

    {:noreply, assign(socket, challenge: challenge, current_user: user, page_title: title)}
  end

  def render(assigns) do
    MobaWeb.LayoutView.render("current_user.html", assigns)
  end

  def update_user!(user, last_challenge_at) do
    user = Accounts.update_user!(user, %{last_challenge_at: last_challenge_at})

    Presence.update_user(self(), user)

    user
  end
end
