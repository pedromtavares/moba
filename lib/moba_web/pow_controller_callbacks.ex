defmodule MobaWeb.PowControllerCallbacks do
  @moduledoc """
  Assigns an existing guest Player to the newly created User record
  """

  use Pow.Extension.Phoenix.ControllerCallbacks.Base
  alias Moba.Game

  def before_respond(Pow.Phoenix.RegistrationController, :create, {:ok, user, conn}, _config) do
    player_id = Plug.Conn.get_session(conn, :player_id)

    if player_id do
      player =
        player_id
        |> Game.get_player!()
        |> Game.update_player!(%{user_id: user.id})
        |> Map.put(:user, user)

      Game.update_hero!(player.current_pve_hero, %{name: user.username})

      if player.pve_tier > 0 do
        Moba.reward_shards!(player, Game.get_quest(1).prize)
        Game.set_player_available!(player)
      end
    end

    Moba.update_pvp_ranking()

    {:ok, user, conn}
  end
end
