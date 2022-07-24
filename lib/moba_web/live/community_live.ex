defmodule MobaWeb.CommunityLive do
  use MobaWeb, :live_view

  def mount(_, _session, socket) do
    with %{assigns: %{channel: channel}} = socket = socket_init(socket) do
      if connected?(socket), do: MobaWeb.subscribe(channel)

      {:ok, socket}
    end
  end

  def handle_event("show-users", _, %{assigns: %{pvp_ranking: users}} = socket) do
    users = if users, do: users, else: Moba.pvp_ranking()
    {:noreply, assign(socket, active_tab: "users", pvp_ranking: users)}
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
          tier: player.pvp_tier,
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

  def handle_info({"general", message}, %{assigns: %{messages: messages}} = socket) do
    {:noreply, assign(socket, messages: messages ++ [message])}
  end

  def handle_info({"updates", message}, %{assigns: %{updates: updates}} = socket) do
    {:noreply, assign(socket, updates: [message] ++ updates)}
  end

  def render(assigns) do
    MobaWeb.CommunityView.render("index.html", assigns)
  end

  defp socket_init(%{assigns: %{current_player: %{user: user}}} = socket) do
    with active_tab = "pve",
         changeset = Accounts.change_message(),
         channel = "community",
         pve_ranking = Game.community_pve_ranking(),
         messages = Accounts.latest_messages(channel, "general", 20) |> Enum.reverse(),
         updates = Accounts.latest_messages(channel, "updates", 20) do
      assign(socket,
        active_tab: active_tab,
        changeset: changeset,
        channel: channel,
        pve_ranking: pve_ranking,
        messages: messages,
        sidebar_code: channel,
        updates: updates,
        pvp_ranking: nil,
        current_user: user
      )
    end
  end
end
