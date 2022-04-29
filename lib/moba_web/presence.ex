defmodule MobaWeb.Presence do
  use Phoenix.Presence,
    otp_app: :moba,
    pubsub_server: Moba.PubSub

  def track_user(pid, user) do
    track(pid, "online", user.id, user_payload(user))
  end

  def update_user(pid, %{id: id} = user) do
    metas =
      get_by_key("online", id)[:metas]
      |> List.first()
      |> Map.merge(user_payload(user))

    update(pid, "online", id, metas)
  end


  defp user_payload(user) do
    %{
      season_tier: user.season_tier,
      season_points: user.season_points,
      user_id: user.id
    }
  end
end
