defmodule MobaWeb.AdminAuth do
  import Phoenix.Controller

  def init(_) do
  end

  def call(conn, _) do
    user = conn.assigns.current_user

    if user && user.is_admin do
      conn
    else
      conn
      |> redirect(to: "/")
    end
  end
end
