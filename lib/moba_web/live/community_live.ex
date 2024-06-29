defmodule MobaWeb.CommunityLive do
  use MobaWeb, :live_view

  alias Moba.Admin

  def mount(_, _session, socket) do
    with %{assigns: %{channel: channel}} = socket = socket_init(socket) do
      if connected?(socket), do: MobaWeb.subscribe(channel)
      if connected?(socket), do: MobaWeb.subscribe("stats")

      Process.send_after(self(), :load_rankings, 100)

      {:ok, socket}
    end
  end

  def handle_event("show-online", _, socket) do
    {:noreply, assign(socket, active_tab: "online")}
  end

  def handle_event("show-pvp", _, socket) do
    {:noreply, assign(socket, active_tab: "pvp")}
  end

  def handle_event("show-pve", _, socket) do
    {:noreply, assign(socket, active_tab: "pve")}
  end

  def handle_event("create-message", params, %{assigns: %{current_player: %{user: user} = player}} = socket) do
    with body = params["message"]["body"],
         length = String.length(body),
         proper_size? = length > 1 && length <= 500 do
      if proper_size? do
        Accounts.create_message!(%{
          body: body,
          author: user.username,
          tier: player.pve_tier,
          channel: "community",
          topic: "general",
          is_admin: user.is_admin,
          user_id: user.id
        })

        {:noreply, assign(socket, changeset: Accounts.change_message(%{user_id: Timex.now()}))}
      else
        {:noreply, socket}
      end
    end
  end

  def handle_event("create-update", params, %{assigns: %{current_user: user}} = socket) do
    if user.is_admin do
      Accounts.create_message!(%{
        title: params["message"]["title"],
        body: params["message"]["body"],
        author: user.username,
        channel: "community",
        topic: "updates",
        is_admin: true,
        user_id: user.id
      })

      {:noreply, assign(socket, changeset: Accounts.change_message(%{user_id: Timex.now()}))}
    end
  end

  def handle_event(
        "delete-message",
        %{"id" => id},
        %{assigns: %{current_user: user, messages: messages, updates: updates}} = socket
      ) do
    with message = Accounts.get_message!(id) do
      if user.is_admin do
        Accounts.delete_message(message)
        {:noreply, assign(socket, messages: messages -- [message], updates: updates -- [message])}
      end
    end
  end

  def handle_event("user-filter", _, %{assigns: %{user_filter: filter}} = socket) do
    new_filter = if filter == :weekly, do: :daily, else: :weekly
    {:noreply, assign(socket, user_filter: new_filter) |> stats_assigns()}
  end

  def handle_event("match-filter", params, socket) do
    with filter = Map.get(params, "type") do
      {:noreply, assign(socket, match_filter: filter) |> stats_assigns()}
    end
  end

  def handle_event("toggle-admin", _, socket) do
    {:noreply, assign(socket, is_admin: !socket.assigns.is_admin)}
  end

  def handle_info({"server", _}, socket) do
    {:noreply, stats_assigns(socket)}
  end

  def handle_info({"general", message}, %{assigns: %{messages: messages, current_player: player}} = socket) do
    {:noreply, assign(socket, messages: messages ++ [message]) |> tick_user(player.user)}
  end

  def handle_info({"updates", message}, %{assigns: %{updates: updates}} = socket) do
    {:noreply, assign(socket, updates: [message] ++ updates)}
  end

  def handle_info(:load_rankings, socket) do
    {:noreply,
     assign(socket,
       pvp_ranking: Moba.season_ranking() |> Enum.filter(& &1.top_hero) |> Enum.take(30),
       pve_ranking: Moba.pve_ranking() |> Enum.take(30)
     )}
  end

  def render(assigns) do
    MobaWeb.CommunityView.render("index.html", assigns)
  end

  defp stats_assigns(%{assigns: %{current_player: %{user: user}}} = socket) do
    with data = Admin.get_server_data(),
         user_filter = socket.assigns[:user_filter] || :weekly,
         match_filter = socket.assigns[:match_filter] || "elite" do
      assign(socket,
        players: data.players,
        guests: data.guests,
        user_filter: user_filter,
        user_stats: data.user_stats[user_filter],
        match_filter: match_filter,
        match_stats: data.match_stats[match_filter],
        duels: data.duels,
        is_admin: user.is_admin
      )
    end
  end

  defp socket_init(%{assigns: %{current_player: %{user: user}}} = socket) do
    with active_tab = "online",
         changeset = Accounts.change_message(),
         channel = "community",
         messages = Accounts.latest_messages(channel, "general", 20) |> Enum.reverse(),
         updates = Accounts.latest_messages(channel, "updates", 20) do
      assign(socket,
        active_tab: active_tab,
        changeset: changeset,
        channel: channel,
        pve_ranking: [],
        messages: messages,
        sidebar_code: channel,
        updates: updates,
        pvp_ranking: [],
        current_user: user,
        notifications: 0
      )
      |> tick_user(user)
      |> stats_assigns()
    end
  end

  defp tick_user(socket, user) do
    user = Accounts.update_user!(user, %{community_seen_at: DateTime.utc_now()})
    assign(socket, user: user)
  end
end
