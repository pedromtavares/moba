defmodule MobaWeb.Presence do
  use Phoenix.Presence,
    otp_app: :moba,
    pubsub_server: Moba.PubSub

  def track_player(pid, player) do
    track(pid, "online", player.id, player_payload(player))
  end

  def update_player(pid, %{id: id} = player) do
    metas =
      get_by_key("online", id)[:metas]
      |> List.first()
      |> Map.merge(player_payload(player))

    update(pid, "online", id, metas)
  end

  defp player_payload(player) do
    %{
      pvp_tier: player.pvp_tier,
      pvp_points: player.pvp_points,
      player_id: player.id
    }
  end
end
