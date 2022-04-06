defmodule MobaWeb.CommunityLiveView do
  use MobaWeb, :live_view

  def mount(_, _session, socket) do
    pve = Game.pve_ranking(21)
    messages = Accounts.latest_messages("general", 20) |> Enum.reverse()
    updates = Accounts.latest_messages("updates", 20) |> Enum.reverse()
    changeset = Accounts.change_message()

    if connected?(socket), do: MobaWeb.subscribe("messages")

    {:ok,
     assign(socket,
       pve: pve,
       users: nil,
       active_tab: "pve",
       changeset: changeset,
       messages: messages,
       updates: updates,
       sidebar_code: "community"
     )}
  end

  def handle_event("show-users", _, socket) do
    users = if socket.assigns.users, do: socket.assigns.users, else: Accounts.ranking(20)
    {:noreply, assign(socket, active_tab: "users", users: users)}
  end

  def handle_event("show-pve", _, socket) do
    {:noreply, assign(socket, active_tab: "pve")}
  end

  def handle_event("create-message", params, %{assigns: %{current_user: user}} = socket) do
    body = params["message"]["body"]
    length = String.length(body)

    if length > 1 && length <= 500 do
      Accounts.create_message!(%{
        body: body,
        author: user.username,
        tier: user.season_tier,
        channel: "general",
        is_admin: user.is_admin,
        user_id: user.id
      })

      {:noreply, assign(socket, changeset: Accounts.change_message(%{user_id: Timex.now()}))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("create-update", params, %{assigns: %{current_user: user}} = socket) do
    body = params["message"]["body"]
    title = params["message"]["title"]

    Accounts.create_message!(%{
      title: title,
      body: body,
      author: user.username,
      tier: user.season_tier,
      channel: "updates",
      is_admin: true,
      user_id: user.id
    })

    {:noreply,
     assign(socket, changeset: Accounts.change_message(%{user_id: Timex.now()}))}
  end

  def handle_event("delete-message", %{"id" => id}, socket) do
    message = Accounts.get_message!(id)
    Accounts.delete_message(message)

    {:noreply,
     assign(socket, messages: socket.assigns.messages -- [message], updates: socket.assigns.updates -- [message])}
  end

  def handle_info({"general", message}, %{assigns: %{messages: messages}} = socket) do
    {:noreply, assign(socket, messages: messages ++ [message])}
  end
  def handle_info({"updates", message}, %{assigns: %{updates: updates}} = socket) do
    {:noreply, assign(socket, updates: updates ++ [message])}
  end

  def render(assigns) do
    MobaWeb.CommunityView.render("index.html", assigns)
  end
end
