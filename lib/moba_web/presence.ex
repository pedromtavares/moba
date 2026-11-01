defmodule MobaWeb.Presence do
  use Phoenix.Presence,
    otp_app: :moba,
    pubsub_server: Moba.PubSub

  def track_player(pid, player) do
    track(pid, "online", player.id, player_payload(player))
  end

  def update_player(pid, %{id: id} = player) do
    update(pid, "online", id, fn meta -> Map.merge(meta, player_payload(player)) end)
  end

  defp player_payload(player) do
    %{
      pvp_tier: player.pvp_tier,
      pvp_points: player.pvp_points,
      player_id: player.id
    }
  end
end
