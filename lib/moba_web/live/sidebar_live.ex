defmodule MobaWeb.SidebarLive do
  use MobaWeb, :live_view

  def mount(_, session, socket) do
    %{"player_id" => player_id, "sidebar_code" => code, "notifications" => notifications} = session

    %{assigns: %{current_player: current_player}} =
      socket = assign_new(socket, :current_player, fn -> Game.get_player!(player_id) end)

    notifications = notifications || Accounts.notification_count(current_player.user)

    if connected?(socket), do: MobaWeb.subscribe("community")

    {:ok, assign(socket, notifications: notifications, sidebar_code: code)}
  end

  def handle_info({"general", _}, %{assigns: %{notifications: count, sidebar_code: code}} = socket)
      when code != "community" do
    {:noreply, assign(socket, notifications: count + 1)}
  end

  def handle_info({"general", _}, socket) do
    {:noreply, socket}
  end

  def render(assigns) do
    MobaWeb.LayoutView.render("sidebar.html", assigns)
  end
end
