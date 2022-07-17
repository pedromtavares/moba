defmodule MobaWeb.CurrentPlayerLive do
  use MobaWeb, :live_view
  alias MobaWeb.Presence

  @default_title "Browser MOBA - Free Strategy Game"

  def mount(_, %{"player_id" => player_id}, socket) do
    %{assigns: %{current_player: current_player}} =
      socket = assign_new(socket, :current_player, fn -> Game.get_player!(player_id) end)

    if connected?(socket) do
      MobaWeb.subscribe("player-#{player_id}")
      Presence.track_player(self(), current_player)
    end

    {:ok, assign(socket, challenge: nil)}
  end

  def handle_event("close", _, socket) do
    {:noreply, assign(socket, challenge: nil)}
  end

  def handle_event("accept", _, %{assigns: %{challenge: challenge, current_player: current_player}} = socket) do
    {player, opponent} =
      if challenge.challenger do
        {current_player, challenge.other}
      else
        {challenge.other, current_player}
      end

    Game.create_pvp_duel!(player, opponent)

    {:noreply, assign(socket, challenge: nil, page_title: @default_title)}
  end

  def handle_event("reject", _, %{assigns: %{challenge: challenge, current_player: current_player}} = socket) do
    MobaWeb.broadcast("player-#{challenge.other_id}", "reject", %{})
    player = update_player!(current_player, Timex.now())

    {:noreply, assign(socket, challenge: nil, player: player, page_title: @default_title)}
  end

  def handle_info({"reject", _}, %{assigns: %{current_player: current_player}} = socket) do
    player = update_player!(current_player, nil)
    {:noreply, assign(socket, challenge: nil, player: player)}
  end

  def handle_info({"duel", %{id: id}}, socket) do
    {:noreply, socket |> push_redirect(to: Routes.live_path(socket, MobaWeb.DuelLive, id))}
  end

  def handle_info(
        {"challenge", %{player_id: player_id, opponent_id: opponent_id}},
        %{assigns: %{current_player: current_player}} = socket
      ) do
    challenge =
      if current_player.id == player_id do
        %{challenger: true, other: Game.get_player!(opponent_id), other_id: opponent_id}
      else
        %{challenger: false, other: Game.get_player!(player_id), other_id: player_id}
      end

    player = update_player!(current_player, Timex.now())
    title = unless challenge.challenger, do: "CHALLENGE!", else: nil

    {:noreply, assign(socket, challenge: challenge, current_player: player, page_title: title)}
  end

  def render(assigns) do
    MobaWeb.LayoutView.render("current_player.html", assigns)
  end

  def update_player!(player, last_challenge_at) do
    player = Game.update_player!(player, %{last_challenge_at: last_challenge_at})

    Presence.update_player(self(), player)

    player
  end
end
