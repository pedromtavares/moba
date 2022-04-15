defmodule MobaWeb.UserLiveAuth do
  import Phoenix.LiveView
  alias Moba.{Accounts, Game}

  def on_mount(:default, _params, %{"user_id" => user_id} = _session, socket) do
    socket =
      assign_new(socket, :current_user, fn ->
        Accounts.get_user!(user_id)
      end)

    user = socket.assigns.current_user

    if user do
      Accounts.set_online_now(user)

      socket =
        assign_new(socket, :current_hero, fn ->
          Game.current_pve_hero(user)
        end)

      {:cont, socket}
    else
      {:halt, redirect(socket, to: "/session/new")}
    end
  end
end
