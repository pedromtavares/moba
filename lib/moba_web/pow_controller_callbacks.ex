defmodule MobaWeb.PowControllerCallbacks do
  @moduledoc """
  Makes sure that the hero created and used by a guest is properly
  transferred to the User record when that guest decides to register
  """

  use Pow.Extension.Phoenix.ControllerCallbacks.Base
  alias Moba.Game

  def before_respond(Pow.Phoenix.RegistrationController, :update, {:ok, user, conn}, _config) do
    guest_user_id = Plug.Conn.get_session(conn, :guest_user_id)

    conn =
      if guest_user_id do
        hero = Game.current_pve_hero(user)
        Game.update_hero!(hero, %{name: user.username})
        Game.generate_daily_quest_progressions!(user.id)
        Plug.Conn.put_session(conn, :guest_user_id, nil)
      else
        conn
      end

    {:ok, user, conn}
  end
end
