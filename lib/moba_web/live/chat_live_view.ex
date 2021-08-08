defmodule MobaWeb.ChatLiveView do
  use MobaWeb, :live_view

  def mount(_, %{"user_id" => user_id}, socket) do
    if connected?(socket) do
      MobaWeb.subscribe("chat")
      MobaWeb.subscribe("user-#{user_id}")
    end

    user = Accounts.get_user!(user_id)

    messages = Accounts.latest_messages()

    IO.inspect(messages)

    count = if length(messages) > 0 do
      user.unread_messages_count
    else
      Accounts.reset_unread_messages_count(user)
      0
    end

    {:ok,
     assign(socket,
       messages: Accounts.latest_messages(),
       changeset: Accounts.change_message(),
       user: user,
       visible: false,
       unread_count: count
     ), temporary_assigns: [alerts: []]}
  end

  def handle_event("show-chat", _, socket) do
    Accounts.reset_unread_messages_count(socket.assigns.user)
    {:noreply, assign(socket, visible: true, unread_count: 0)}
  end

  def handle_event("close-chat", %{"key" => "Escape"}, %{assigns: %{visible: true}} = socket) do
    Accounts.reset_unread_messages_count(socket.assigns.user)
    {:noreply, assign(socket, visible: false, unread_count: 0)}
  end

  def handle_event("close-chat", _, %{assigns: %{visible: true}} = socket) do
    Accounts.reset_unread_messages_count(socket.assigns.user)
    {:noreply, assign(socket, visible: false, unread_count: 0)}
  end

  def handle_event("close-chat", _, socket) do
    {:noreply, socket}
  end

  def handle_event("send", params, %{assigns: %{user: user}} = socket) do
    hero = Game.current_hero(user)
    body = params["message"]["body"]
    length = String.length(body)

    if length > 1 && length <= 250 do
      author = if hero, do: hero.name, else: user.username

      message =
        Accounts.create_message!(%{
          body: body,
          user_id: user.id,
          author: author,
          tier: hero && hero.league_tier,
          code: hero && hero.avatar.code,
          image: hero && hero.avatar.image,
          is_admin: user.is_admin
        })

      Accounts.increment_unread_messages_count_for_all_online_except(user)

      {:noreply,
       assign(socket,
         changeset: Accounts.change_message(%{user_id: Timex.now()}),
         messages: [message] ++ socket.assigns.messages
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    message = Accounts.get_message!(id)
    Accounts.delete_message(message)
    {:noreply, assign(socket, messages: socket.assigns.messages -- [message])}
  end

  def handle_info(
        {"message", message},
        %{assigns: %{messages: messages, unread_count: count, visible: visible, alerts: alerts, user: user}} = socket
      ) do
    {alerts, new_count} =
      if message.user_id == user.id do
        {alerts, 0}
      else
        alert = Map.put(message, :type, "message")
        {[alert] ++ alerts, count + 1}
      end

    {:noreply, assign(socket, messages: [message] ++ messages, unread_count: new_count, alerts: alerts)}
  end

  def handle_info({"alert", alert}, socket) do
    {:noreply, assign(socket, alerts: [alert] ++ socket.assigns.alerts)}
  end

  def render(assigns) do
    MobaWeb.ChatView.render("index.html", assigns)
  end
end
