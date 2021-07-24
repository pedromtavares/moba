defmodule MobaWeb.PowControllerCallbacks do
  @moduledoc """
  Makes sure that the hero created and used by a guest is properly
  transferred to the User record when that guest decides to register
  """

  use Pow.Extension.Phoenix.ControllerCallbacks.Base
  alias Moba.{Game, Accounts}

  def before_respond(Pow.Phoenix.RegistrationController, :create, {:ok, user, conn}, _config) do
    guest_user_id = Plug.Conn.get_session(conn, :guest_user_id)

    conn =
      if guest_user_id do
        guest = Accounts.get_user!(guest_user_id)
        hero = guest && Game.current_pve_hero(guest)
        guest = hero.user

        Game.update_hero!(hero, %{name: user.username, user_id: user.id})

        Accounts.update_user!(guest, %{current_pve_hero_id: nil})

        Accounts.update_user!(user, %{
          tutorial_step: guest.tutorial_step,
          experience: guest.experience,
          level: guest.level,
          current_pve_hero_id: hero.id
        })

        Plug.Conn.put_session(conn, :guest_user_id, nil)
      else
        conn
      end

    {:ok, user, conn}
  end
end
